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

/// A strength the user can pick for what they use.
///
/// `mg` is nil for "not sure", which is a deliberate option rather than a gap:
/// the number is on the Drug Facts panel and most people are not holding the
/// tin when they answer. An unsure answer still yields a usable cap — see
/// `OnboardingAnswers.strengthMgPerUnit` — because refusing to proceed until
/// someone fetches a tin is how a run gets abandoned.
struct StrengthOption: Identifiable, Equatable, Sendable {
    let mg: Double?
    let label: String

    var id: String { label }

    /// Pouch strengths, which is what the design asks for. Other sources need
    /// their own sets and their own question — a cigarette has no meaningful
    /// "per piece" strength to choose.
    static let pouch: [StrengthOption] = [
        StrengthOption(mg: 2, label: "2 mg"),
        StrengthOption(mg: 3, label: "3 mg"),
        StrengthOption(mg: 4, label: "4 mg"),
        StrengthOption(mg: 6, label: "6 mg"),
        StrengthOption(mg: 8, label: "8 mg or more"),
        StrengthOption(mg: nil, label: "Not sure"),
    ]

    /// What an unsure answer is worth. The mid-range pouch, and the number the
    /// helper text tells the user it will assume, so the screen and the maths
    /// cannot disagree.
    static let assumedWhenUnsure: Double = 3
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
    var strength: StrengthOption?

    /// True once the user has said enough for the run to continue.
    var hasChosenSources: Bool { !sources.isEmpty }

    /// The strength to plan with, in label milligrams.
    ///
    /// Nil only while the question is unanswered. Once answered it always
    /// resolves to a number, because "not sure" is an answer — it means "use
    /// the middle of the range and let me correct it later", not "stop".
    var strengthMgPerUnit: Double? {
        guard let strength else { return nil }
        return strength.mg ?? StrengthOption.assumedWhenUnsure
    }

    /// True when the strength above is an assumption rather than something the
    /// user read off a tin. The app owes them a chance to correct it, and a
    /// number it invented must not be presented as one they gave.
    var strengthIsAssumed: Bool { strength?.mg == nil && strength != nil }

    func toggle(_ source: NicotineSource) {
        if sources.contains(source) {
            sources.remove(source)
        } else {
            sources.insert(source)
        }
    }
}
