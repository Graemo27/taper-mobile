import Foundation
import Observation

/// How far back the graph looks, today included.
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

/// Reads the finished days the graph draws — the last week or month up to
/// yesterday — and builds the trend around today handed in fresh.
///
/// Today is an *input*, not a fetch. The first draft cached (day, span) with
/// today inside the window, which meant a check-in made after the read never
/// reached the graph until midnight or a toggle: the one bar somebody watches
/// respond to their own taps was the one bar that could not. Finished days do
/// not change and are cached; today changes all day and is passed in from the
/// same record home's cards already read, so the graph and the figure above
/// it can never disagree.
///
/// Its own record rather than a reach into `PastDaysRecord`, whose window is
/// the list's pagination. The two share nothing but the stores they read.
@Observable
@MainActor
final class TrendRecord {
    /// Separate from an empty trend: a week with nothing logged is an
    /// ordinary week, a week that could not be read is an apology. The text
    /// says which apology — a build with no backend is not a bad connection,
    /// and "try again" on it would be asking somebody to retry a fact.
    private(set) var isUnavailable = false
    private(set) var apologyText: String?
    private(set) var span: TrendSpan = .week

    /// The finished days in hand, oldest first, and the window they answer
    /// for. Kept together: data that has outlived its window is refused
    /// rather than drawn under the wrong day or the wrong toggle.
    private var pastDays: [DayRollup]?
    private var history: PlanHistory?
    private var pastWindow: Window?

    /// Which run a read is for — the yesterday it ends at and the reach — so
    /// midnight and the toggle each invalidate it and nothing else does. The
    /// same shape `PastDaysRecord` keys on, for the same reason: every
    /// stale-publish defect in that type was something written after an await
    /// by an operation no longer current.
    private var loaded: Window?

    private struct Window: Equatable {
        let end: Date
        let span: TrendSpan
    }

    private let checkIns: (any CheckInReading)?
    private let plans: (any PlanVersionReading)?
    private let calendar: Calendar
    private let today: () -> Date

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

    /// The graph, built from the cached finished days and today's own
    /// entries. Nil while the window has not loaded — or has stopped being
    /// the current one, because bars mislabeled "today" are worse than a
    /// moment of loading.
    func trend(today todayEntries: [StoredCheckIn]) -> Trend? {
        guard let pastDays, let history, pastWindow == currentWindow else { return nil }
        let todayStart = calendar.startOfDay(for: today())
        let todaysRollup = DayRollup(
            day: todayStart, entries: todayEntries, capMg: history.cap(on: todayStart)
        )
        return Trend(days: pastDays + [todaysRollup], calendar: calendar, today: todayStart)
    }

    /// Switches the reach and reads it.
    func show(_ span: TrendSpan) async {
        self.span = span
        await load()
    }

    /// Reads the window, once per (yesterday, span).
    func load() async {
        guard let checkIns, let plans else {
            isUnavailable = true
            apologyText = Self.noBackend
            return
        }
        guard let window = currentWindow else { return }
        guard loaded != window else { return }
        loaded = window

        // One fewer than the span: today is the last bar and is not fetched.
        guard let start = calendar.date(
            byAdding: .day, value: -(window.span.rawValue - 2), to: window.end
        ) else { return }

        do {
            let entries = try await checkIns.entries(from: start, to: window.end)
            let read = PlanHistory(versions: try await plans.versions(), calendar: calendar)

            // Published only if this is still the run being asked for: the
            // day can turn and the toggle can move while both reads are open.
            guard currentWindow == window else { return }

            let byDay = Dictionary(grouping: entries, by: \.loggedOn)
            pastDays = Self.days(from: start, to: window.end, calendar: calendar).map { day in
                DayRollup(
                    day: day,
                    entries: byDay[PlanDay.wireFormat(day, timeZone: calendar.timeZone)] ?? [],
                    capMg: read.cap(on: day)
                )
            }
            history = read
            pastWindow = window
            isUnavailable = false
            apologyText = nil
        } catch {
            guard currentWindow == window else { return }
            // Forgotten either way, so coming back re-reads: the cache stops
            // a finished read repeating, not a failed one being retried.
            loaded = nil
            guard !Task.isCancelled else { return }
            // Data from an older window is dropped rather than kept: after a
            // failed midnight re-read, yesterday's run drawn as today is a
            // graph lying about which day it is. Same-window data survives a
            // failed refresh, because it is still true.
            if pastWindow != window {
                pastDays = nil
                history = nil
                pastWindow = nil
            }
            isUnavailable = pastDays == nil
            apologyText = isUnavailable
                ? "Couldn't load the \(span.word.lowercased()). Check your connection and try again."
                : nil
        }
    }

    static let noBackend = "This build has no backend configured, so there is nothing to draw."

    /// Yesterday and the reach, or nil before there is a yesterday.
    private var currentWindow: Window? {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today()))
            .map { Window(end: $0, span: span) }
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
