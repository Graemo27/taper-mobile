import Foundation
import Observation

/// Reads the day before today: its check-ins, what they came to, and the cap it
/// was measured against.
///
/// Separate from `TodayRecord`, which owns a day still being written to — a
/// pending selection, an optimistic removal — none of which is true of a day
/// that is over.
@Observable
@MainActor
final class YesterdayRecord {
    private(set) var rollup: DayRollup?
    /// Why yesterday is missing, when it is. Separate from an empty day, which
    /// is an ordinary thing for a day to be.
    private(set) var isUnavailable = false

    private let checkIns: (any CheckInReading)?
    private let plans: (any PlanVersionReading)?
    private let calendar: Calendar
    private let today: () -> Date
    /// Which yesterday is in hand, rather than merely whether one is.
    ///
    /// A boolean here was a bug: this record outlives midnight, so an app left
    /// open overnight would keep serving the day before last under a heading
    /// that says "Yesterday" — with that day's cap beside it. Keyed on the date
    /// instead, so the answer is refused the moment it stops being about the
    /// day being asked for.
    private var loadedDay: Date?

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

    /// The day before the one in hand, at its start.
    private var yesterday: Date? {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today()))
    }

    /// Reads yesterday, once per yesterday.
    ///
    /// Re-reads when the date has turned and not otherwise: a finished day does
    /// not change while somebody looks at it, so returning to the log is free.
    /// Nothing here schedules the turn — a timer firing at midnight would be a
    /// second source of truth about what day it is, which is the same reason
    /// `TodayRecord` leaves it to the screen to re-read.
    func load() async {
        guard let checkIns, let plans, let yesterday else { return }
        guard loadedDay != yesterday else { return }
        loadedDay = yesterday

        do {
            // Both reads before anything is published, so the section never
            // draws a total against a ceiling it has not fetched yet.
            let entries = try await checkIns.entries(on: yesterday)
            let history = PlanHistory(versions: try await plans.versions(), calendar: calendar)
            rollup = DayRollup(
                day: yesterday,
                entries: entries,
                capMg: history.cap(on: yesterday)
            )
            // Cleared on the way out, not only set on the way in. A retry that
            // works has to take the apology down with it.
            isUnavailable = false
        } catch {
            // Abandoned, not failed — this is driven by a view's `task`, so it
            // is cancelled exactly when somebody navigates away.
            guard !Task.isCancelled else {
                // Forgotten, so navigating back re-reads rather than showing a
                // section that never arrived.
                loadedDay = nil
                return
            }
            // Forgotten here too. The cache is there to stop a *finished*
            // day being re-read, not to make a failed one permanent — without
            // this, one dropped connection means the section stays broken for
            // the rest of the day however many times somebody comes back to it.
            loadedDay = nil

            // And the day already in hand goes with it. Reaching the read at
            // all means the guard let this through, which means the held rollup
            // is for a day that is no longer yesterday — so keeping it would
            // draw the day before last under a heading that says Yesterday,
            // with that day's cap beside it. The same lie the date-keyed cache
            // above exists to prevent, arriving by the other door.
            rollup = nil
            isUnavailable = true
        }
    }
}
