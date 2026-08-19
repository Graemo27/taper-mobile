import Foundation

/// What the user is quitting.
///
/// Both licensed forms appear here because someone can arrive already on gum or
/// lozenges and want off them — that is a thing to quit, not a treatment. What
/// they are *treating* with is asked separately, and the two must not be
/// inferred from each other.
enum NicotineSource: String, CaseIterable, Identifiable, Sendable {
    case pouches, cigarettes, vape, dip, nrt, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pouches: return "Pouches"
        case .cigarettes: return "Cigarettes"
        case .vape: return "Vape"
        case .dip: return "Dip or chew"
        case .nrt: return "Nicotine gum or lozenges"
        case .other: return "Something else"
        }
    }
}

/// Everything onboarding collects, accumulated as the user moves through it.
///
/// One object rather than a value threaded screen to screen: the run branches —
/// a quit date is optional, and O5a only appears once a treatment is relevant —
/// so screens need to read answers given several steps earlier.
///
/// Deliberately holds answers, not a plan. Turning these into a taper is
/// `TaperPlanner`'s job, and keeping that boundary means the plan stays a pure
/// function of stated inputs rather than something the UI can nudge.
@Observable
final class OnboardingAnswers {
    var sources: Set<NicotineSource> = []

    /// True once the user has said enough for the run to continue.
    var hasChosenSources: Bool { !sources.isEmpty }

    func toggle(_ source: NicotineSource) {
        if sources.contains(source) {
            sources.remove(source)
        } else {
            sources.insert(source)
        }
    }
}
