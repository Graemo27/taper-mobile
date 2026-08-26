import Foundation

/// L2's graph, as numbers: a run of days ending today, each a bar against the
/// stepping cap.
///
/// Everything the chart draws is decided here rather than in the view, because
/// a graph whose claims can only be seen by rendering it is a graph whose
/// claims are not checked — and this one makes three: the bars, the verdict in
/// the heading, and the sentence under it.
struct Trend: Equatable, Sendable {
    /// One day of the graph.
    struct Bar: Equatable, Sendable {
        let day: Date
        /// The day's height, as a share of the tallest thing on the chart.
        let fraction: Double
        /// Where that day's cap sits on the same scale, or nil when no plan
        /// covered it — a missing segment, never a line at zero.
        let capFraction: Double?
        /// Today is drawn filled where every other day is tinted.
        let isToday: Bool
        /// "S", "M" — the weekday letter under the bar, localized.
        let label: String
    }

    let bars: [Bar]
    /// "Trending down", "Trending up", "Holding steady" — or "Nothing logged
    /// yet" while every day is empty. A heading that always said "Trending
    /// down" would be the app lying on its best-looking card.
    let headline: String
    /// The sentence under the letters. Names what the dotted line is, says how
    /// many capped days landed under it, and only claims the shape is working
    /// when most of them did.
    let caption: String

    /// Builds the graph from a run of days, oldest first, today last.
    init(days: [DayRollup], calendar: Calendar, today: Date) {
        // One scale for bars and cap line both. Scaling them separately would
        // draw an over-cap day under its own ceiling, which is the one
        // relationship this chart exists to show.
        let top = max(
            days.map(\.loggedMg).max() ?? 0,
            days.compactMap(\.capMg).max() ?? 0
        )

        let todayStart = calendar.startOfDay(for: today)
        var letters = calendar.veryShortStandaloneWeekdaySymbols
        if letters.count != 7 { letters = ["S", "M", "T", "W", "T", "F", "S"] }
        bars = days.map { day in
            Bar(
                day: day.day,
                fraction: top > 0 ? day.loggedMg / top : 0,
                capFraction: top > 0 ? day.capMg.map { $0 / top } : day.capMg.map { _ in 0 },
                isToday: calendar.startOfDay(for: day.day) == todayStart,
                label: letters[calendar.component(.weekday, from: day.day) - 1]
            )
        }

        headline = Self.verdict(on: days.map(\.loggedMg))
        caption = Self.sentence(for: days)
    }

    /// Second half against first, with a band for "steady" so one lozenge
    /// either way does not flip the verdict.
    private static func verdict(on totals: [Double]) -> String {
        guard totals.contains(where: { $0 > 0 }) else { return "Nothing logged yet" }
        let half = totals.count / 2
        let early = totals.prefix(half)
        let late = totals.suffix(totals.count - half)
        let earlyAverage = early.isEmpty ? 0 : early.reduce(0, +) / Double(early.count)
        let lateAverage = late.isEmpty ? 0 : late.reduce(0, +) / Double(late.count)

        if lateAverage < earlyAverage * 0.95 { return "Trending down" }
        if lateAverage > earlyAverage * 1.05 { return "Trending up" }
        return "Holding steady"
    }

    /// Counts only days a cap covered — a day with no ceiling cannot be under
    /// one — and claims the shape is working only when most of them were.
    private static func sentence(for days: [DayRollup]) -> String {
        let capped = days.filter { $0.capMg != nil }
        guard !capped.isEmpty else {
            return "Dotted line is your daily cap. No cap covered these days."
        }
        let under = capped.filter { !$0.isOver }.count
        let opening = "Dotted line is your daily cap, stepping down."
        let count = "\(under) of \(capped.count) day\(capped.count == 1 ? "" : "s") under"
        return under * 2 > capped.count
            ? "\(opening) \(count) — the shape is working."
            : "\(opening) \(count)."
    }
}
