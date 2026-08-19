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

    /// The unit this source is counted in, in the words its user already uses.
    ///
    /// Nobody knows their vape in milligrams, so nobody is asked for them.
    /// `modality-shapes-data` is direct about why this matters: whatever a
    /// tracker appears to want, it will get — a milligram field produces an
    /// invented milligram, and the plan is then built on it.
    var unitLabel: String {
        switch self {
        case .pouches: return "Pouches a day"
        case .cigarettes: return "Cigarettes a day"
        case .vape: return "Puffs a day"
        case .dip: return "Packs a day"
        case .nrt: return "Pieces a day"
        case .other: return "Times a day"
        }
    }

    /// How much one tap moves the count. Puffs run to dozens, so stepping them
    /// one at a time would make the honest answer the tedious one.
    var step: Int {
        self == .vape ? 5 : 1
    }

    /// Where the stepper opens. A plausible middle, so the common case is a
    /// nudge rather than a climb from zero.
    var defaultAmount: Int {
        switch self {
        case .vape: return 40
        case .cigarettes: return 10
        case .pouches, .nrt: return 6
        case .dip, .other: return 3
        }
    }

    /// Estimated milligrams per unit, for sources with nothing printed to read.
    ///
    /// Only the cigarette figure has a source: an average cigarette delivers
    /// 1–3 mg and 20 a day absorbs 20–40 mg, so 1.5 is the midpoint consistent
    /// with both (`nicotine-dose-reference`). **The vape and dip figures are
    /// estimates with no source behind them** — the vault holds no
    /// pharmacokinetic data for per-puff or per-portion delivery, which is
    /// filed as G9 under Q12. They are deliberately rough, and that roughness
    /// is part of why the app moves people onto something with a printed
    /// number. Do not present any of these to the user as a measurement.
    var estimatedMgPerUnit: Double? {
        switch self {
        case .cigarettes: return 1.5
        case .vape: return 0.15
        case .dip: return 3
        case .other: return 1
        // Printed on the pack — the user tells us, we do not guess.
        case .pouches, .nrt: return nil
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

    /// The set to offer for one source. Keyed by source rather than by the
    /// selection as a whole: someone quitting pouches *and* gum has two printed
    /// strengths to give, and answering once for both would apply a 6 mg pouch
    /// to gum that comes in 2 and 4.
    static func options(for source: NicotineSource) -> [StrengthOption] {
        source == .pouches ? pouch : nrt
    }

    /// What an unsure answer is worth for that source — the mid-range pouch, or
    /// the common gum. Named in the helper text, so the screen and the maths
    /// cannot disagree; and always a value from the matching options list,
    /// because an assumption must be an answer the user could have given.
    static func assumedWhenUnsure(for source: NicotineSource) -> Double {
        source == .pouches ? 3 : 2
    }
}

/// How soon after waking the first one happens.
///
/// The single most predictive item in the standard dependence index, which is
/// why `TaperPlanner` treats the earliest band as sufficient for high
/// dependence on its own rather than merely weighting it.
///
/// Each option carries the minutes the planner reasons about, so the wording
/// and the arithmetic cannot drift apart. The values sit inside their band
/// rather than on its edge — 20 for "within 30 minutes" rather than 30 — so a
/// later change to a threshold does not silently reclassify an answer.
struct FirstUseOption: Identifiable, Equatable, Sendable {
    let minutes: Int
    let label: String

    var id: String { label }

    static let all: [FirstUseOption] = [
        FirstUseOption(minutes: 3, label: "It's the first thing I do"),
        FirstUseOption(minutes: 20, label: "Within 30 minutes"),
        FirstUseOption(minutes: 45, label: "Within an hour"),
        FirstUseOption(minutes: 180, label: "A few hours in"),
        FirstUseOption(minutes: 360, label: "Afternoon or later"),
    ]
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
    /// The printed strength given for each source that has one.
    var strengths: [NicotineSource: StrengthOption] = [:]
    /// The exact figure per source, once an open-ended option is narrowed down.
    var exactStrengths: [NicotineSource: Double] = [:]
    /// How much of each source, in that source's own unit.
    var amounts: [NicotineSource: Int] = [:]
    /// How soon after waking the first one happens (O4).
    var firstUse: FirstUseOption?

    /// True once the user has said enough for the run to continue.
    var hasChosenSources: Bool { !sources.isEmpty }

    /// The strength to plan with for one source, in label milligrams.
    ///
    /// Nil only while that source's question is unanswered. Once answered it
    /// always resolves to a number, because "not sure" is an answer — it means
    /// "use the middle of the range and let me correct it later", not "stop".
    func strengthMgPerUnit(for source: NicotineSource) -> Double? {
        guard let option = strengths[source] else { return nil }
        if let exact = exactStrengths[source], option.isAtLeast { return exact }
        return option.mg ?? StrengthOption.assumedWhenUnsure(for: source)
    }

    /// True when that source's strength is an assumption rather than something
    /// read off a pack. The app owes the user a chance to correct it, and a
    /// number it invented must not be presented as one they gave.
    func strengthIsAssumed(for source: NicotineSource) -> Bool {
        guard let option = strengths[source] else { return false }
        if option.mg == nil { return true }
        // A floor that has not been narrowed down is still an assumption, and
        // the least safe kind: it under-states rather than over-states.
        return option.isAtLeast && exactStrengths[source] == nil
    }

    /// The sources still owing a number before the run can continue.
    var sourcesNeedingExactStrength: [NicotineSource] {
        orderedSources.filter { source in
            (strengths[source]?.isAtLeast ?? false) && exactStrengths[source] == nil
        }
    }

    /// Every source that should be asked for a printed strength.
    var sourcesWithPrintedStrength: [NicotineSource] {
        orderedSources.filter(\.usesPerUnitStrength)
    }

    /// The sources to ask about, in a stable order. A `Set` has none, and rows
    /// that reshuffle between renders are unusable.
    var orderedSources: [NicotineSource] {
        NicotineSource.allCases.filter { sources.contains($0) }
    }

    func amount(for source: NicotineSource) -> Int {
        amounts[source] ?? source.defaultAmount
    }

    func setAmount(_ value: Int, for source: NicotineSource) {
        amounts[source] = max(0, value)
    }

    /// The starting daily figure the planner works from.
    ///
    /// An index rather than a dose, and knowingly so. Pouches contribute label
    /// milligrams off the pack; everything else contributes an estimate, and
    /// two of those estimates have no source (Q12/G9). Summing across products
    /// is already an index rather than a measurement per
    /// `label-dose-is-not-delivered-dose`; summing across *bases* — label for
    /// one, estimated delivery for another — is a second mixing on top.
    ///
    /// It is accepted because the alternative is asking people for numbers they
    /// do not have, and because the roughness applies only to the sources the
    /// app is steering them off anyway. It must never be shown as a precise
    /// figure.
    var startingCapMg: Double {
        orderedSources.reduce(0) { total, source in
            let perUnit = source.estimatedMgPerUnit ?? strengthMgPerUnit(for: source) ?? 0
            return total + perUnit * Double(amount(for: source))
        }
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
        strengths = strengths.filter { sources.contains($0.key) }
        exactStrengths = exactStrengths.filter { sources.contains($0.key) }
        amounts = amounts.filter { sources.contains($0.key) }
    }
}
