import Foundation
import Observation

/// What the app knows about today's log.
///
/// An empty day is `ready` and empty — that is how every day starts. Being
/// unable to read it is `unavailable`, and the two must not be conflated: a
/// screen showing "nothing logged yet" over a failed read would invite somebody
/// to log a second time against a day it could not see.
enum DayStatus: Equatable, Sendable {
    case loading
    case ready
    case unavailable(String)
}

/// Owns today: what has been logged, what is selected against it, and writing
/// the two together.
///
/// The selection is held here rather than beside it because clearing it on a
/// successful write and keeping it through a failed one are rules about the
/// write, and two owners would put half of each rule in a view.
///
/// The day is read through a closure rather than captured once. An app left
/// open across midnight should roll over on its own — "new day, new cap;
/// yesterday stays in yesterday" — and a record holding a stale `Date` would
/// keep adding to a day that ended hours ago.
@Observable
@MainActor
final class TodayRecord {
    /// What the last read returned, and the day it was asked about.
    ///
    /// Private as a pair, because either one alone is a trap: rows without the
    /// day they belong to are rows that look like today's forever.
    private var loadedEntries: [StoredCheckIn] = []
    private var loadedDay: Date?

    /// Today's entries — empty when the last read was for a different day.
    ///
    /// A record that outlives midnight holds rows that belong to yesterday, and
    /// measuring them against today's ceiling reports a day somebody has not
    /// had yet. Yesterday stays in yesterday, so those rows stop counting the
    /// moment the date turns rather than when something happens to re-read
    /// them.
    ///
    /// Empty rather than stale is the safe direction: at the moment of rollover
    /// today genuinely has nothing on it, and under-reporting for the seconds
    /// before a reload is a smaller lie than carrying a whole day across.
    var entries: [StoredCheckIn] { hasRolledOver ? [] : loadedEntries }

    /// True once the calendar day has turned since the last read.
    ///
    /// Exposed so the screen can re-read. Nothing here schedules that: a timer
    /// firing at midnight is a second source of truth about what day it is, and
    /// this type already has one.
    var hasRolledOver: Bool {
        guard let loadedDay else { return false }
        return !calendar.isDate(loadedDay, inSameDayAs: day())
    }
    private(set) var status: DayStatus = .loading
    /// Why the last check-in did not land. Separate from `status`, which is
    /// about reading — a day that read fine and a write that failed are
    /// different sentences, and only one of them has a retry.
    private(set) var writeFailure: String?
    /// What is chosen on the pad. Held here rather than beside it, because the
    /// tally is the one place the day and the selection have to be read
    /// together, and two owners would make that a join at every call site.
    let selection: PadSelection

    private let store: (any CheckInStoring)?
    private let day: () -> Date
    /// How a day is bounded. The device's, matching the zone the store writes
    /// `logged_on` in — a record that disagreed with the column about where a
    /// day ends would roll over at the wrong moment.
    private let calendar: Calendar
    private var isLoading = false
    private var isWriting = false

    init(
        store: (any CheckInStoring)?,
        selection: PadSelection = PadSelection(),
        calendar: Calendar = .current,
        day: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.selection = selection
        self.calendar = calendar
        self.day = day
    }

    /// Today, with the pending selection folded in, measured against the cap
    /// the plan gives.
    ///
    /// The ceiling is passed rather than held, so this type never needs to know
    /// about the plan — and the one number both screens quote comes from a
    /// single place.
    func tally(ceilingMg: Double) -> TodaysTally {
        TodaysTally(entries: entries, pending: selection.pending, ceilingMg: ceilingMg)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let store else {
            status = .unavailable(Self.noBackend)
            return
        }

        status = .loading
        do {
            // Read once and kept together, so the rows and the day they answer
            // for cannot drift apart.
            let asked = day()
            loadedEntries = try await store.entries(on: asked)
            loadedDay = asked
            status = .ready
        } catch {
            // Abandoned, not failed. This read is driven by a view's `task`, so
            // it is cancelled exactly when somebody navigates away, and
            // reporting that would put "check your connection" in front of a
            // connection that was fine. The flag rather than a `catch is
            // CancellationError`, because a request already in flight arrives
            // as `URLError.cancelled` and only the flag covers both routes.
            guard !Task.isCancelled else { return }
            status = .unavailable("Couldn't load today. Check your connection and try again.")
        }
    }

    /// Puts the pad back to resting.
    ///
    /// Clears the failure too. A message about a write nobody is attempting any
    /// more is a message about nothing.
    func clear() {
        selection.clear()
        writeFailure = nil
    }

    /// Logs what is selected.
    ///
    /// The selection survives a failed write on purpose: it is what the retry
    /// re-sends, and clearing it would make somebody re-tap a count they had
    /// already tapped out.
    func checkIn() async {
        guard let entry = selection.pending, !isWriting else { return }

        guard let store else {
            writeFailure = Self.noBackend
            return
        }

        isWriting = true
        defer { isWriting = false }
        writeFailure = nil

        do {
            // The day read now, not the one the last load asked about.
            // Somebody logging at ten past midnight is logging on the new day,
            // whatever day the rows on screen came from.
            let today = day()
            let written = try await store.log(CheckInDraft(pending: entry, day: today))

            // Appended rather than re-read: the row that comes back is the row
            // that was written, and a second round trip to learn what we were
            // just told would put a spinner between the tap and the total.
            //
            // Onto the day it was written for, which is not always the day in
            // hand. A tap that crosses midnight starts the new day rather than
            // joining rows that stopped being today's while the screen was open.
            if calendar.isDate(loadedDay ?? today, inSameDayAs: today) {
                loadedEntries.append(written)
            } else {
                loadedEntries = [written]
            }
            loadedDay = today
            status = .ready
            selection.clear()
        } catch {
            // Abandoned, not refused — but not succeeded either. The row may or
            // may not have landed, so the day is left as it was and the
            // selection stays: the next load settles which it was.
            guard !Task.isCancelled else { return }
            writeFailure = "Couldn't log that. Check your connection and try again."
        }
    }

    private static let noBackend = "This build has no backend configured, so nothing can be logged."
}
