import Foundation

/// Whether the run ends at a date or holds where it is.
///
/// The one branch in onboarding with a routing consequence: choosing to reduce
/// first skips the quit-date screen entirely, and `TaperPlanner` treats a nil
/// date as a supported state rather than an unfinished one.
///
/// Both are offered as real plans rather than a real one and a fallback. Almost
/// all cessation evidence was measured on people already motivated to quit, and
/// most nicotine users are not in that state — a product that only speaks to
/// the ready is addressing the smaller half of its users
/// (`readiness-to-quit-spectrum`).
///
/// This is not a claim that the two are equally effective. A bare taper is
/// inferior to a quit date and its danger is deferring the attempt
/// (`taper-vs-abrupt`). The honest position is that someone who will not set a
/// date today is better served reducing than closing the app, and the door
/// stays open — which is what the copy says and what the model has to allow.
enum PlanShape: String, CaseIterable, Identifiable, Sendable {
    case quitDate, reduceFirst

    var id: String { rawValue }

    /// True when the run continues on to ask for a date.
    var needsQuitDate: Bool { self == .quitDate }

    var label: String {
        switch self {
        case .quitDate: return "Set a quit date now"
        case .reduceFirst: return "Reduce first — date later"
        }
    }

    /// What each choice actually does, in the app's own behaviour. Conditional
    /// phrasing on the second — "if and when you're ready" — is the framing the
    /// one trial that targeted the not-yet-ready scored best on, and it costs
    /// nothing to adopt.
    var detail: String {
        switch self {
        case .quitDate:
            return "The taper steps down toward it, and the countdown becomes your home screen."
        case .reduceFirst:
            return "Hold steady, step down when it feels easy, and pick a date if and when you're ready."
        }
    }
}
