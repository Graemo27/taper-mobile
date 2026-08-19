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

    /// Whether "how strong is one?" is a question this source can answer.
    ///
    /// A pouch or a lozenge has a printed per-piece figure. A cigarette does
    /// not — its dose is a property of the cigarette, not a choice — and a vape
    /// is measured in mg/mL against unmeasured puffs. Asking those users to
    /// pick a pouch strength would make them invent a number, and the plan
    /// would then be built on it.
    var usesPerUnitStrength: Bool {
        switch self {
        case .pouches, .nrt: return true
        case .cigarettes, .vape, .dip, .other: return false
        }
    }

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
    /// True when the label names a floor rather than a value — "8 mg or more".
    /// Planning on the floor would size the cap for 8 mg when the pouch might
    /// be 12, and a cap set below what someone actually uses is one they blow
    /// on day one. Failing a schedule was associated with worse outcomes than
    /// never being given one, so this asks for the real number instead.
    var isAtLeast: Bool = false

    var id: String { label }

    /// Strengths pouches are actually sold in.
    static let pouch: [StrengthOption] = [
        StrengthOption(mg: 2, label: "2 mg"),
        StrengthOption(mg: 3, label: "3 mg"),
        StrengthOption(mg: 4, label: "4 mg"),
        StrengthOption(mg: 6, label: "6 mg"),
        StrengthOption(mg: 8, label: "8 mg or more", isAtLeast: true),
        StrengthOption(mg: nil, label: "Not sure"),
    ]

    /// Strengths licensed gum and lozenges are sold in. Separate, because
    /// offering a gum user 3 or 6 mg — pouch strengths their product does not
    /// come in — quietly asks them to fabricate: every option must be an answer
    /// someone could read off a pack.
    static let nrt: [StrengthOption] = [
        StrengthOption(mg: 1, label: "1 mg"),
        StrengthOption(mg: 1.5, label: "1.5 mg"),
        StrengthOption(mg: 2, label: "2 mg"),
        StrengthOption(mg: 4, label: "4 mg"),
        StrengthOption(mg: nil, label: "Not sure"),
    ]

    /// The set to offer, given what the user is quitting. Pouches win a mixed
    /// selection: they are the product this app is primarily for, and O3
    /// collects each source's amount separately regardless.
    static func options(for sources: Set<NicotineSource>) -> [StrengthOption] {
        sources.contains(.pouches) ? pouch : nrt
    }

    /// What an unsure answer is worth, per product family — the mid-range
    /// pouch, or the common gum. Named in the helper text, so the screen and
    /// the maths cannot disagree; and always a value from the matching options
    /// list, because the assumption must be an answer the user could have given.
    static func assumedWhenUnsure(for sources: Set<NicotineSource>) -> Double {
        sources.contains(.pouches) ? 3 : 2
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
    var strength: StrengthOption?
    /// The exact figure, once an open-ended option has been narrowed down.
    var exactStrengthMg: Double?

    /// True once the user has said enough for the run to continue.
    var hasChosenSources: Bool { !sources.isEmpty }

    /// The strength to plan with, in label milligrams.
    ///
    /// Nil only while the question is unanswered. Once answered it always
    /// resolves to a number, because "not sure" is an answer — it means "use
    /// the middle of the range and let me correct it later", not "stop".
    var strengthMgPerUnit: Double? {
        guard let strength else { return nil }
        if let exact = exactStrengthMg, strength.isAtLeast { return exact }
        return strength.mg ?? StrengthOption.assumedWhenUnsure(for: sources)
    }

    /// True when the strength above is an assumption rather than something the
    /// user read off a tin. The app owes them a chance to correct it, and a
    /// number it invented must not be presented as one they gave.
    var strengthIsAssumed: Bool {
        guard let strength else { return false }
        if strength.mg == nil { return true }
        // A floor that has not been narrowed down is still an assumption, and
        // the least safe kind: it under-states rather than over-states.
        return strength.isAtLeast && exactStrengthMg == nil
    }

    /// True while an open-ended answer still needs a number before the run can
    /// continue. Distinct from "not sure", which resolves on its own.
    var needsExactStrength: Bool {
        (strength?.isAtLeast ?? false) && exactStrengthMg == nil
    }

    func toggle(_ source: NicotineSource) {
        if sources.contains(source) {
            sources.remove(source)
        } else {
            sources.insert(source)
        }
        // A strength for a deselected source must not survive into the plan.
        // The routing skips the screen for such runs, so a stale value would
        // never be shown or corrected — just used.
        if !sources.contains(where: { $0.usesPerUnitStrength }) {
            strength = nil
            exactStrengthMg = nil
        }
    }
}
