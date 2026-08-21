import Foundation
import Observation

/// What the app knows about the user's plan, and what it has done about it.
///
/// A rendered state for each, because the interesting ones are all the ones the
/// happy path skips. Two of them are easy to conflate and must not be: having
/// no plan is a reason to run onboarding, and being unable to find out is not.
enum PlanStatus: Equatable, Sendable {
    /// Looking, at launch. Nothing has been decided yet.
    case checking
    /// Checked, and this person has no plan. Onboarding is the right answer.
    case absent
    case saving
    /// A write that failed. The sentence to show — never the underlying error,
    /// because a user cannot act on a Postgres code and one on screen reads as
    /// the app breaking rather than as something to try again.
    case saveFailed(String)
    /// A plan exists, either found at launch or just written, and this is it.
    /// Carried rather than merely flagged, because every screen behind this
    /// state is built from the row and re-reading it to draw one would be a
    /// second trip for something already in hand.
    case present(StoredTaperPlan)
    /// The check itself failed, so whether a plan exists is unknown.
    ///
    /// Deliberately not `absent`. Treating an unanswered question as a "no"
    /// would walk somebody through twelve questions they have already answered
    /// and then overwrite the plan they could not be shown.
    case unknown(String)

    /// True once a plan is known to exist. Spelled out because the case now
    /// carries a value, and `== .present` no longer compiles.
    var isPresent: Bool {
        if case .present = self { return true }
        return false
    }
}

/// Owns the app's one plan: finding it at launch, and writing it once.
///
/// Separate from the view so the states can be asserted. The failure and
/// in-flight branches are the ones no screenshot will ever catch — they need a
/// store that fails on demand, which a real backend cannot be asked to do.
@Observable
@MainActor
final class PlanRecord {
    private(set) var status: PlanStatus = .checking

    /// Nil when the build has no backend, which is a distinct condition from a
    /// request that failed. The app has already shipped once configured only
    /// while a test drove it, and the whole cost of that was the two looking
    /// identical on screen.
    private let store: (any TaperPlanStoring)?
    /// The pad, seeded by the same tap that writes the plan.
    private let pad: (any PadKeyStoring)?

    /// One lookup at a time.
    ///
    /// The retry on the failure screen starts a load, which sets `checking`,
    /// which renders the looking-for-it screen, whose `task` starts another —
    /// so a single tap issues two reads. They can finish in either order, and a
    /// stale failure landing after a fresh success would put the error screen
    /// back in front of someone whose plan had just been found.
    ///
    /// The guard lives here rather than in the view because it is a rule about
    /// the operation. A view can be re-created for reasons this type does not
    /// control, and one that fires `task` twice would otherwise be a defect in
    /// a different file.
    private var isLoading = false

    init(store: (any TaperPlanStoring)?, pad: (any PadKeyStoring)? = nil) {
        self.store = store
        self.pad = pad
    }

    /// Looks for a plan already on file.
    ///
    /// Called once at launch. Anything other than a clean answer leaves the
    /// status `unknown` rather than `absent`, because the cost of guessing
    /// wrong in that direction is a user redoing onboarding on top of a plan
    /// they cannot see.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let store else {
            status = .unknown(Self.noBackend)
            return
        }

        status = .checking
        do {
            status = try await store.currentPlan().map(PlanStatus.present) ?? .absent
        } catch {
            // Abandoned, not failed. This read is driven by a view's `task`,
            // and reporting a cancellation would put "check your connection"
            // in front of somebody whose connection was never the problem.
            // The flag rather than `catch is CancellationError`, because a
            // request already in flight arrives as `URLError.cancelled`, and
            // asking the flag covers both routes.
            //
            // Only the read. `submit` is left alone deliberately: a write
            // cancelled in flight has genuinely unknown outcome, and reporting
            // it as failed sends the user to a retry that upserts — which is
            // the safe direction to be wrong in.
            guard !Task.isCancelled else { return }
            status = .unknown("Couldn't check for your plan. Check your connection and try again.")
        }
    }

    /// Writes the pad and the plan, once.
    ///
    /// Returns immediately if a write is already in flight or a plan is already
    /// present. The CTA is disabled in both states, but a disabled button is a
    /// rendering decision and this is the rule — two taps landing either side
    /// of the first render would otherwise write twice.
    func submit(_ run: CompletedRun) async {
        guard status != .saving, !status.isPresent else { return }

        guard let store, let pad else {
            status = .saveFailed(Self.noBackend)
            return
        }

        status = .saving
        do {
            // The pad first and the plan second, because that is the order
            // that recovers from a half-finished write.
            //
            // Seeding is idempotent — a pad with keys already on it comes back
            // untouched — so a pad written without a plan is a state the next
            // run walks straight through: onboarding finds no plan, asks
            // again, seeds nothing new, and saves. The other order strands
            // people. A saved plan with an empty pad routes the next launch
            // to the home screen, which never asks the questions again and has
            // no way to fill the pad, and there is nothing to tap for the rest
            // of the taper.
            _ = try await pad.seed(run.padKeys)
            status = .present(try await store.save(run.draft))
        } catch {
            // Deliberately one sentence for every failure. The distinctions the
            // client can actually draw — offline, refused, timed out — are not
            // ones the user acts on differently, and inventing a cause the
            // state cannot know is how copy starts lying.
            status = .saveFailed("Couldn't save your plan. Check your connection and try again.")
        }
    }

    /// Clears a failure so the plan can be offered again. Not a retry itself —
    /// the retry is the user tapping, which is the only thing that should cause
    /// a second write.
    func dismissFailure() {
        if case .saveFailed = status { status = .absent }
    }

    private static let noBackend = "This build has no backend configured, so nothing can be saved."
}
