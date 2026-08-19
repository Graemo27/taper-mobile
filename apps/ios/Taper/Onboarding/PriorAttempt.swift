import Foundation

/// Something the user has already tried, to stop.
///
/// Recorded, not scored. Nothing in the evidence supports treating a count of
/// past attempts as a dependence item, and inventing a rule here would be the
/// plan reacting to an answer the user was told had no wrong version.
///
/// `neverTried` is one of the options rather than an empty selection, which is
/// what lets this screen hold Continue until it has been answered — see
/// `Trigger`, where the absence of such an option is exactly why that screen
/// cannot gate.
enum PriorAttempt: String, CaseIterable, Identifiable, Sendable {
    case coldTurkey, cuttingDown, gumOrLozenge, patches, prescription, neverTried

    var id: String { rawValue }

    /// True for the answer that excludes every other one. Holding "never really
    /// tried" alongside "cold turkey" is two contradictory answers to one
    /// question.
    var isNone: Bool { self == .neverTried }

    var label: String {
        switch self {
        case .coldTurkey: return "Cold turkey"
        case .cuttingDown: return "Cutting down on my own"
        case .gumOrLozenge: return "Nicotine gum or lozenges"
        case .patches: return "Patches"
        // Named, because someone who has been prescribed one of these has tried
        // something more effective than anything this app offers, and the
        // option list should not quietly omit it.
        case .prescription: return "Prescription meds (varenicline, bupropion)"
        case .neverTried: return "Never really tried"
        }
    }
}
