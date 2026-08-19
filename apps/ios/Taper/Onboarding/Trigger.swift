import Foundation

/// A moment someone reaches for one, in the situations people actually name.
///
/// Situations rather than feelings. "Stress" alone is a state someone has to
/// interpret before they can answer; "work stress" and "driving" are things
/// that either happened today or did not, which is the difference between a
/// question people answer accurately and one they answer approximately.
///
/// Nothing in the plan reads these. They exist for the craving screen, which
/// promises to meet the user in the moment — and a moment the app was never
/// told about is one it cannot meet them in.
enum Trigger: String, CaseIterable, Identifiable, Sendable {
    case drinks, meals, work, driving, others, boredom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .drinks: return "With coffee or a drink"
        case .meals: return "Right after meals"
        case .work: return "Work stress"
        case .driving: return "Driving"
        case .others: return "Being around other people using"
        case .boredom: return "Boredom or downtime"
        }
    }
}
