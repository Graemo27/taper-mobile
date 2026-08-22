import Foundation

/// A day that has already happened, read back in a line: how many check-ins
/// were on it, what they came to, and the ceiling it was measured against.
///
/// Today gets `TodaysTally` instead, which folds in a pending tap this has no
/// use for.
struct DayRollup: Equatable, Sendable {
    /// The day itself, at its start.
    let day: Date
    let checkInCount: Int
    /// Sources only, the same rule the cap counts by: treatment is logged and
    /// never added in.
    let loggedMg: Double
    /// What the day was measured against, or nil when no plan covered it.
    ///
    /// Nil is not zero. A day before the plan began has no ceiling, and drawing
    /// one as zero would paint every check-in on it as over.
    let capMg: Double?

    init(day: Date, entries: [StoredCheckIn], capMg: Double?) {
        self.day = day
        self.capMg = capMg
        checkInCount = entries.count
        loggedMg = entries
            .filter { $0.ledger == .source }
            .reduce(0) { $0 + $1.totalMg }
    }

    /// True only when there is a ceiling to be over.
    ///
    /// A day with no plan cannot be over one, however much is on it — saying
    /// otherwise would be the app judging days it was not keeping.
    var isOver: Bool {
        guard let capMg else { return false }
        return loggedMg > capMg
    }

    /// How full the day's bar is, clamped so an over-cap day fills it rather
    /// than running past the end.
    ///
    /// Unlike today's meter this does not rescale to show an overflow tail: a
    /// past day is a fact rather than a decision in progress, so the bar reports
    /// full and the colour says the rest.
    var fraction: Double {
        guard let capMg, capMg > 0 else { return 0 }
        return min(1, loggedMg / capMg)
    }

    /// "4 check-ins" — the count alone, because the milligrams are said beside
    /// it in the same row.
    var countText: String {
        "\(checkInCount) check-\(checkInCount == 1 ? "in" : "ins")"
    }

    /// The line under the bar: where the day landed, and nothing about what it
    /// says about the person.
    ///
    /// The board reads "Under cap. That's 3 days in a row." The streak needs a
    /// range this screen does not read yet, so the first half ships and the
    /// second waits rather than a number being guessed at.
    var summarySentence: String {
        guard capMg != nil else { return "No cap was set for this day." }
        return isOver ? "Over cap. Noted, not judged." : "Under cap."
    }

    /// "10 of 12.5 mg", or the total alone when nothing was measuring it.
    /// The weekday, for a day far enough back to be named by one.
    var weekdayText: String {
        day.formatted(.dateTime.weekday(.wide))
    }

    /// "Aug 19" — the date without the year, which is noise on a week.
    var dateText: String {
        day.formatted(.dateTime.month(.abbreviated).day())
    }

    var totalText: String {
        guard let capMg else { return "\(loggedMg.clean) mg" }
        return "\(loggedMg.clean) of \(capMg.clean) mg"
    }
}
