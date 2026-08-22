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
    /// Why the last removal did not land. Its own sentence, because a failed
    /// delete and a failed write send somebody to different buttons.
    private(set) var removeFailure: String?
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
    private(set) var isWriting = false
    /// Entries whose removal is in flight.
    ///
    /// A day read back from the server still contains them until the delete
    /// commits, so a reload landing mid-removal would put a row back on screen
    /// that somebody has just taken off it.
    private var removing: Set<Int> = []

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
            // Minus anything being removed right now: the server has not
            // committed those deletes yet, and putting the rows back on screen
            // would undo a correction in front of the person making it.
            loadedEntries = try await store.entries(on: asked)
                .filter { !removing.contains($0.id) }
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

    /// The day read back in a line: how many entries, and where they leave it.
    ///
    /// Counts every entry, including treatment — the list shows what happened,
    /// and a patch taken is something that happened. The milligrams beside it
    /// are the ones that count against the cap, which is why the two numbers
    /// can look unrelated and are not.
    func summary(ceilingMg: Double) -> String {
        let count = entries.count
        let noun = count == 1 ? "check-in" : "check-ins"
        let tally = tally(ceilingMg: ceilingMg)
        return "\(count) \(noun) · \(tally.loggedMg.clean) of \(ceilingMg.clean) mg"
    }

    /// Takes an entry back.
    ///
    /// Removed from the day before the request, and put back if it fails. The
    /// alternative — waiting on the server before the row leaves the screen —
    /// makes correcting a mis-tap feel like it might not have worked, and the
    /// most common reason somebody deletes is that they just tapped the wrong
    /// key and want it gone now.
    ///
    /// Restored to its own place rather than appended, because the day is in
    /// the order it was logged and a corrected entry that reappears at the
    /// bottom looks like a second one — and only onto the day it came off.
    func remove(_ entry: StoredCheckIn) async {
        guard let store, loadedEntries.contains(entry) else { return }

        // The day this entry belongs to, read before the request rather than
        // after it. Midnight can pass while a removal is open, and the entry
        // is only ever restorable onto the day it was removed from.
        let removedFrom = loadedDay

        loadedEntries.removeAll { $0.id == entry.id }
        // Held for as long as the request is, and read by `load()`. A reload
        // landing mid-removal answers from the server, which still has the row
        // until the delete commits — so without this the entry comes back on
        // screen after a delete that worked, or arrives twice after one that
        // did not.
        removing.insert(entry.id)
        removeFailure = nil
        defer { removing.remove(entry.id) }

        do {
            try await Task { try await store.remove(entry.id) }.value
        } catch {
            // Said either way, before deciding whether there is anywhere to put
            // the row back. The delete did not commit, so the entry is still on
            // the server whether or not this screen can still show it, and a
            // failed removal that reports nothing is one somebody assumes
            // worked.
            removeFailure = "Couldn't remove that. Check your connection and try again."

            // Only onto the day it came off. A reload landing after midnight
            // replaces the day entirely, and restoring into that would file
            // yesterday's entry under today and charge today's cap for it —
            // rollover undone by the one path that writes to the day without
            // consulting the clock. Yesterday's row is not lost: the delete
            // failed, so it is still on the server, and yesterday will read it
            // back.
            guard let removedFrom, let loadedDay,
                  calendar.isDate(loadedDay, inSameDayAs: removedFrom) else { return }

            // Back into id order rather than at a remembered index. A reload
            // can have replaced the whole day while this was in flight, and an
            // index from before that is a position in an array that no longer
            // exists. The day is ordered by id — the read asks for it that way
            // and a new entry always has the highest — so the order can be
            // rebuilt from the entry itself.
            let at = loadedEntries.firstIndex { $0.id > entry.id } ?? loadedEntries.count
            loadedEntries.insert(entry, at: at)
        }
    }

    /// What the check-in button says.
    ///
    /// The pending total rather than the count, because the number that
    /// matters is the one going against the cap — "Check in · 3 mg" is what
    /// the meter above it is about to move by.
    var checkInTitle: String {
        guard let pending = selection.pending else { return "Check in" }
        return "Check in · \(pending.totalMg.clean) mg"
    }

    /// Whether there is anything to check in.
    ///
    /// Here rather than in the view because it is a rule about the operation,
    /// not about rendering. A disabled button is how it is *shown*; `checkIn()`
    /// enforces the same thing whether or not anybody drew it that way.
    var canCheckIn: Bool { selection.pending != nil && !isWriting }

    /// Puts the pad back to resting.
    ///
    /// Clears the failure too. A message about a write nobody is attempting any
    /// more is a message about nothing.
    func clear() {
        selection.clear()
        writeFailure = nil
        removeFailure = nil
    }

    /// Logs what is selected.
    ///
    /// The selection survives a failed write on purpose: it is what the retry
    /// re-sends, and clearing it would make somebody re-tap a count they had
    /// already tapped out.
    ///
    /// **The write itself cannot be abandoned.** It runs in an unstructured
    /// task, so a screen going away does not cancel it. Two reasons, and the
    /// second is the load-bearing one:
    ///
    /// A tap that has been made should be recorded. Dropping a log because a
    /// view disappeared would lose something the user did on purpose.
    ///
    /// And an abandoned write has no safe recovery. If the insert commits
    /// before the cancellation reaches us, the retry writes it again —
    /// `check_ins` has no operation id and nothing unique to conflict on. It
    /// cannot be reconciled by content either: two 3 mg pouches half a minute
    /// apart is an ordinary afternoon, so a duplicate is indistinguishable
    /// from a second genuine tap. Letting the write finish removes the state
    /// rather than trying to recover from it.
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
            // Not `try await store.log(...)` directly: an unstructured task
            // does not inherit cancellation, which is the whole point.
            let draft = CheckInDraft(pending: entry, day: today)
            let written = try await Task { try await store.log(draft) }.value

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
            // No cancellation branch, because there is no longer a cancelled
            // case to catch — the write above is not abandonable. A guard here
            // would be a branch no test could reach, which is where defects
            // hide.
            writeFailure = "Couldn't log that. Check your connection and try again."
        }
    }

    private static let noBackend = "This build has no backend configured, so nothing can be logged."
}
