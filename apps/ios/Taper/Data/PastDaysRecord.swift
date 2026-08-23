import Foundation
import Observation

/// Reads the run of days before today: their check-ins, what each came to, and
/// the cap each was measured against.
///
/// Separate from `TodayRecord`, which owns a day still being written to — a
/// pending selection, an optimistic removal — none of which is true of a day
/// that is over.
@Observable
@MainActor
final class PastDaysRecord {
    /// Newest first, which is the order the log draws them and the order the
    /// window is built in.
    private(set) var rollups: [DayRollup] = []
    /// Why the days are missing, when they are. Separate from an empty run,
    /// which is an ordinary thing for a week to be.
    private(set) var isUnavailable = false

    /// How many days a window starts at, and how many each "show earlier" adds.
    ///
    /// A week, because that is the span somebody can hold in their head. The
    /// window never grows on its own: one that did would make the read cost
    /// depend on how long somebody had been tapering, so going further back is
    /// a control they press.
    static let windowLength = 7

    /// How many days are being asked for now.
    private(set) var length = windowLength

    /// True while a "show earlier" request is open.
    ///
    /// Its own flag rather than reusing whatever `load()` does, because this is
    /// the only read somebody triggers by pressing something — every other one
    /// happens because a screen appeared, and a spinner for those would flicker
    /// on every visit.
    private(set) var isLoadingEarlier = false

    /// Whether there is anything earlier to show.
    ///
    /// False once the window reaches the first day of the plan. There is no
    /// point offering to load days that pre-date somebody's taper — nothing was
    /// being measured then, so every one of them would draw as a day with no
    /// ceiling.
    private(set) var hasEarlier = false

    private let checkIns: (any CheckInReading)?
    private let plans: (any PlanVersionReading)?
    private let calendar: Calendar
    private let today: () -> Date
    /// Which window is in hand, rather than merely whether one is.
    ///
    /// A boolean here was a bug: this record outlives midnight, so an app left
    /// open overnight would keep serving the day before last under a heading
    /// that says "Yesterday" — with that day's cap beside it. Keyed on the date
    /// instead, so the answer is refused the moment it stops being about the
    /// day being asked for.
    ///
    /// A window and not just a day, because "show earlier" asks for the same
    /// end with a longer reach — and a key that only knew the end would refuse
    /// that as already loaded. Four separate defects in this type have been the
    /// same mistake in different clothes: something written after an `await` by
    /// an operation that is no longer the current one. Naming the whole
    /// identity once is what stops there being a fifth.
    private var loaded: Window?

    /// Which run of days is being asked for: where it ends, and how far back it
    /// reaches.
    private struct Window: Equatable {
        let end: Date
        let length: Int
    }

    /// The window as it stands now, or nil before there is a yesterday to end
    /// it at.
    private var currentWindow: Window? {
        yesterday.map { Window(end: $0, length: length) }
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

    /// The day before the one in hand, at its start — the newest day in the
    /// window, and the one the cache is keyed on.
    private var yesterday: Date? {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today()))
    }

    /// The oldest day in the window.
    private func windowStart(endingAt end: Date, length: Int) -> Date? {
        calendar.date(byAdding: .day, value: -(length - 1), to: end)
    }

    /// Reads the window, once per yesterday.
    ///
    /// Re-reads when the date has turned and not otherwise: a finished day does
    /// not change while somebody looks at it, so returning to the log is free.
    /// Nothing here schedules the turn — a timer firing at midnight would be a
    /// second source of truth about what day it is, which is the same reason
    /// `TodayRecord` leaves it to the screen to re-read.
    func load() async {
        guard let checkIns, let plans, let window = currentWindow else { return }
        guard loaded != window else { return }
        loaded = window

        guard let start = windowStart(endingAt: window.end, length: window.length) else { return }
        let yesterday = window.end

        do {
            // Both reads before anything is published, so no day draws a total
            // against a ceiling that has not been fetched yet — and one request
            // for the span rather than one per day, so a week arrives as a week
            // rather than as seven separate successes and failures.
            let entries = try await checkIns.entries(from: start, to: yesterday)
            let history = PlanHistory(versions: try await plans.versions(), calendar: calendar)

            // Nothing is published unless this is still the window being asked
            // for. Two awaits sit above this line and `yesterday` was read
            // before them, so a read that starts at 23:59 answers for a day
            // that has passed by the time it lands — and publishing it would
            // put the day before last under a heading that says Yesterday, the
            // same lie as the other two by the only door left.
            //
            // One check, not two. A newer load overtaking this one cannot be
            // told apart here: it can only exist because the day turned, since
            // a second load for the *same* yesterday returns at the guard
            // above. Mutation testing found the ownership check and the cache
            // clear that went with it were both unreachable, so they are gone
            // rather than sitting untested.
            guard currentWindow == window else { return }

            // Grouped by `logged_on`, which is the day the reader was in when
            // they tapped — never by `created_at`, which is the server's clock
            // and would file the last tap of a night under tomorrow.
            let byDay = Dictionary(grouping: entries, by: \.loggedOn)
            rollups = Self.days(from: start, to: yesterday, calendar: calendar).map { day in
                let wire = PlanDay.wireFormat(day, timeZone: calendar.timeZone)
                return DayRollup(day: day, entries: byDay[wire] ?? [], capMg: history.cap(on: day))
            }
            // Whether there is anything earlier is a fact about the plan, not
            // about the rows: a week with nothing in it still has days before
            // it if the taper started before them.
            hasEarlier = history.planStart.map { calendar.startOfDay(for: start) > $0 } ?? false

            // Cleared on the way out, not only set on the way in. A retry that
            // works has to take the apology down with it.
            isUnavailable = false
        } catch {
            // A failure belongs to the window that asked for it. This read may
            // have been overtaken — started before midnight, failing after a
            // newer one has already loaded the day correctly — and everything
            // below would then tear down a good window and replace it with an
            // apology for a request nobody is waiting on.
            //
            // The worse half of the same check on the success path: there a
            // stale read published old data, here a stale *failure* destroys
            // current data.
            guard currentWindow == window else { return }

            // Abandoned, not failed — this is driven by a view's `task`, so it
            // is cancelled exactly when somebody navigates away.
            guard !Task.isCancelled else {
                // Forgotten, so navigating back re-reads rather than showing a
                // section that never arrived.
                loaded = nil
                return
            }
            // Forgotten here too. The cache is there to stop a *finished*
            // day being re-read, not to make a failed one permanent — without
            // this, one dropped connection means the section stays broken for
            // the rest of the day however many times somebody comes back to it.
            loaded = nil

            // And the day already in hand goes with it. Reaching the read at
            // all means the guard let this through, which means the held rollup
            // is for a day that is no longer yesterday — so keeping it would
            // draw the day before last under a heading that says Yesterday,
            // with that day's cap beside it. The same lie the date-keyed cache
            // above exists to prevent, arriving by the other door.
            rollups = []
            isUnavailable = true
        }
    }

    /// Asks for another week further back.
    ///
    /// Reloads the whole window rather than fetching only the new days and
    /// appending. One request that returns a consistent run beats two that can
    /// disagree at the seam — and the seam is a day boundary, which is where
    /// every bug in this type has been.
    func showEarlier() async {
        guard !isLoadingEarlier, hasEarlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }

        length += Self.windowLength
        await load()
    }

    /// Every day in the span, newest first.
    ///
    /// Built from the calendar rather than from the rows, so a day with nothing
    /// on it still gets a place in the list. A week with a gap in it drawn as
    /// six days would read as a week that was shorter than it was.
    private static func days(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: end)
        let first = calendar.startOfDay(for: start)
        while cursor >= first {
            days.append(cursor)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return days
    }
}
