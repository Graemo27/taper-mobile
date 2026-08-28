import Foundation

/// L8a — two minutes of riding out a craving, as a value.
///
/// Derived from a start and a clock rather than accumulated from ticks, and
/// that is the whole design. A tick counter is a second source of truth about
/// time: it stops when the app is backgrounded, drifts when a frame is missed,
/// and disagrees with the clock the moment either happens. Somebody who locks
/// their phone for ninety seconds of a two-minute craving has ridden out ninety
/// seconds of it — coming back to a timer that says otherwise is the app
/// arguing with them about their own experience.
///
/// So one captured baseline, exactly as `state-that-changes-with-no-event`
/// concluded from the midnight bug: scheduling from time and initialising from
/// time have to read the same instant.
struct Ride: Equatable, Sendable {
    /// The board's number: "Ride it out · 2 min".
    static let span: TimeInterval = 120

    /// What the sequence asks for, in order.
    ///
    /// Every one of them points at the body. The largest mediation study on
    /// file found the whole effect of a cessation app ran through acceptance
    /// of *physical sensations and emotions* — thoughts did not mediate at all
    /// — so a step asking somebody to reason about their craving would be the
    /// one part of this with evidence against it.
    enum Step: Int, CaseIterable, Sendable {
        case notice, name, ride

        var eyebrow: String {
            switch self {
            case .notice: return "NOTICE"
            case .name: return "NAME"
            case .ride: return "RIDE"
            }
        }

        var instruction: String {
            switch self {
            case .notice:
                return "Where is it? Chest, throat, hands. Find its edges."
            case .name:
                return "Give it a size and a shape. Sharp or dull. Rising or level."
            case .ride:
                return "Stay with it. You're not fixing it — you're outlasting it."
            }
        }
    }

    /// How long has actually passed, clamped to the span at both ends.
    ///
    /// Clamped rather than trusted: a clock can go backwards — a manual change,
    /// an NTP correction — and a negative elapsed would draw a ring past full
    /// and a countdown above two minutes.
    let elapsed: TimeInterval

    init(startedAt: Date, now: Date) {
        elapsed = min(max(now.timeIntervalSince(startedAt), 0), Self.span)
    }

    var isDone: Bool { elapsed >= Self.span }

    /// How much of the ring is drawn: 0 at the start, 1 at the end.
    var fraction: Double { elapsed / Self.span }

    /// The step this moment belongs to. Three equal thirds, and the last one
    /// keeps the final instant rather than rolling off the end of the list.
    var step: Step {
        let third = Self.span / Double(Step.allCases.count)
        let index = min(Int(elapsed / third), Step.allCases.count - 1)
        return Step(rawValue: index) ?? .ride
    }

    /// "1:12" — what is left, rounded up so it reads 2:00 at the start and
    /// only says 0:00 when it is actually over.
    var remainingText: String {
        let remaining = Int((Self.span - elapsed).rounded(.up))
        return "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
    }
}
