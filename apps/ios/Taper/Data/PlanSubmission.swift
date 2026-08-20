import Foundation

/// What has happened to the plan the user agreed to.
///
/// A rendered state for each, because the interesting ones are the two the
/// happy path skips. A save that fails silently leaves someone believing the
/// app is tracking a plan it never wrote down, which is worse than not offering
/// to save at all.
enum PlanSaveState: Equatable, Sendable {
    case idle
    case saving
    /// The sentence to show. Never the underlying error: a user cannot act on
    /// a Postgres error code, and one on screen reads as the app breaking
    /// rather than as something to try again.
    case failed(String)
    case saved
}

/// Owns the one write onboarding makes, and the state the screen renders from
/// it.
///
/// Separate from the view so the states can be asserted. The failure and
/// in-flight branches are the ones no screenshot will ever catch — they need a
/// store that fails on demand, which a real backend cannot be asked to do.
@Observable
@MainActor
final class PlanSubmission {
    private(set) var state: PlanSaveState = .idle

    /// Nil when the build has no backend, which is a distinct condition from a
    /// write that failed. The app has shipped once already configured only
    /// while a test was driving it, and the whole cost of that was the two
    /// looking identical on screen.
    private let store: (any TaperPlanWriting)?

    init(store: (any TaperPlanWriting)?) { self.store = store }

    /// Writes the plan, once.
    ///
    /// Returns immediately if a write is already in flight or has already
    /// succeeded. The CTA is disabled in both states, but a disabled button is
    /// a rendering decision and this is the rule — two taps landing either side
    /// of the first render would otherwise write twice.
    func submit(_ draft: TaperPlanDraft) async {
        guard state != .saving, state != .saved else { return }

        guard let store else {
            state = .failed("This build has no backend configured, so nothing can be saved.")
            return
        }

        state = .saving
        do {
            _ = try await store.save(draft)
            state = .saved
        } catch {
            // Deliberately one sentence for every failure. The distinctions the
            // client can actually draw — offline, refused, timed out — are not
            // ones the user acts on differently, and inventing a cause the
            // state cannot know is how copy starts lying.
            state = .failed("Couldn't save your plan. Check your connection and try again.")
        }
    }

    /// Clears a failure so the CTA is offerable again. Not a retry itself —
    /// the retry is the user tapping, which is the only thing that should
    /// cause a second write.
    func dismissFailure() {
        if case .failed = state { state = .idle }
    }
}
