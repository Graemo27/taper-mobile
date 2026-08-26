import Foundation
import Observation

/// How far back the graph looks.
enum TrendSpan: Int, CaseIterable, Sendable {
    case week = 7
    case month = 30

    var word: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// Reads the run of days the graph draws: the last week or month, today
/// included.
///
/// Its own record rather than a reach into `PastDaysRecord`, whose window is
/// the list's pagination — "show earlier" grows it seven days at a press, and
/// a graph toggling that length under the list would move a control somebody
/// else is holding. The two share nothing but the stores they read.
@Observable
@MainActor
final class TrendRecord {
    private(set) var trend: Trend?
    /// Separate from an empty trend: a week with nothing logged is an ordinary
    /// week, a week that could not be read is an apology.
    private(set) var isUnavailable = false
    private(set) var span: TrendSpan = .week

    private let checkIns: (any CheckInReading)?
    private let plans: (any PlanVersionReading)?
    private let calendar: Calendar
    private let today: () -> Date

    /// Which run is in hand — the day it ends and the reach — so midnight and
    /// a span toggle each invalidate it and nothing else does. The same shape
    /// `PastDaysRecord` keys its cache on, for the same four-defects reason:
    /// every stale-publish bug in that type was something written after an
    /// `await` by an operation that was no longer the current one.
    private var loaded: Window?

    private struct Window: Equatable {
        let end: Date
        let span: TrendSpan
    }

    init(
        checkIns: (any CheckInReading)?,
        plans: (any PlanVersionReading)?,
        calendar: Calendar = .current,
        today: @escaping () -> Date = { Date() }
    ) {
        self.checkIns = checkIns
        self.plans = plans
        self.calendar = calendar
        self.today = today
    }

    /// Switches the reach and reads it. The old trend stays on screen while
    /// the new one loads — a graph that blinks to empty on every toggle reads
    /// as the data vanishing.
    func show(_ span: TrendSpan) async {
        // A month is not a week with a different name: the old bars are
        // cleared rather than left drawing under the wrong toggle. Within a
        // span the old trend does stay through a failed re-read.
        if span != self.span { trend = nil }
        self.span = span
        await load()
    }

    /// Reads the window, once per (day, span).
    func load() async {
        guard let checkIns, let plans else { return }
        let window = Window(end: calendar.startOfDay(for: today()), span: span)
        guard loaded != window else { return }
        loaded = window

        guard let start = calendar.date(
            byAdding: .day, value: -(window.span.rawValue - 1), to: window.end
        ) else { return }

        do {
            let entries = try await checkIns.entries(from: start, to: window.end)
            let history = PlanHistory(versions: try await plans.versions(), calendar: calendar)

            // Published only if this is still the run being asked for: the day
            // can turn and the toggle can move while both reads are open.
            guard Window(end: calendar.startOfDay(for: today()), span: span) == window else { return }

            let byDay = Dictionary(grouping: entries, by: \.loggedOn)
            let days = Self.days(from: start, to: window.end, calendar: calendar).map { day in
                DayRollup(
                    day: day,
                    entries: byDay[PlanDay.wireFormat(day, timeZone: calendar.timeZone)] ?? [],
                    capMg: history.cap(on: day)
                )
            }
            trend = Trend(days: days, calendar: calendar, today: window.end)
            isUnavailable = false
        } catch {
            guard Window(end: calendar.startOfDay(for: today()), span: span) == window else { return }
            // Forgotten either way, so coming back re-reads: the cache stops a
            // finished read repeating, not a failed one from being retried.
            loaded = nil
            guard !Task.isCancelled else { return }
            isUnavailable = trend == nil
        }
    }

    /// Every day from `start` through `end`, oldest first.
    private static func days(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day <= end, days.count <= 366 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
