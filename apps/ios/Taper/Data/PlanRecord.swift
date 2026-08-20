import Foundation

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
    /// A plan exists, either found at launch or just written.
    case present
    /// The check itself failed, so whether a plan exists is unknown.
    ///
    /// Deliberately not `absent`. Treating an unanswered question as a "no"
    /// would walk somebody through twelve questions they have already answered
    /// and then overwrite the plan they could not be shown.
    case unknown(String)
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

    init(store: (any TaperPlanStoring)?) { self.store = store }

    /// Looks for a plan already on file.
    ///
    /// Called once at launch. Anything other than a clean answer leaves the
    /// status `unknown` rather than `absent`, because the cost of guessing
    /// wrong in that direction is a user redoing onboarding on top of a plan
    /// they cannot see.
    func load() async {
        guard let store else {
            status = .unknown(Self.noBackend)
            return
        }

        status = .checking
        do {
            status = try await store.currentPlan() == nil ? .absent : .present
        } catch {
            status = .unknown("Couldn't check for your plan. Check your connection and try again.")
        }
    }

    /// Writes the plan, once.
    ///
    /// Returns immediately if a write is already in flight or a plan is already
    /// present. The CTA is disabled in both states, but a disabled button is a
    /// rendering decision and this is the rule — two taps landing either side
    /// of the first render would otherwise write twice.
    func submit(_ draft: TaperPlanDraft) async {
        guard status != .saving, status != .present else { return }

        guard let store else {
            status = .saveFailed(Self.noBackend)
            return
        }

        status = .saving
        do {
            _ = try await store.save(draft)
            status = .present
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
