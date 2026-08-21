import Foundation
import Testing
@testable import Taper

/// A check-in store that does what the test needs and counts what it was asked.
private final class FakeCheckIns: CheckInStoring, @unchecked Sendable {
    var existing: [StoredCheckIn] = []
    var readFails = false
    var writeFails = false
    /// Holds a write open, so a second can be attempted while the first is in
    /// flight.
    var writeHangs = false
    /// Holds a read open, so a second can be attempted while the first is in
    /// flight.
    var readHangs = false

    private let lock = NSLock()
    private var _writes: [CheckInDraft] = []
    private var _reads = 0
    /// Every draft it was asked to log, in order. Drafts rather than a count,
    /// so a retry sending a different quantity is distinguishable from a repeat.
    var writes: [CheckInDraft] { lock.withLock { _writes } }
    var reads: Int { lock.withLock { _reads } }

    func entries(on day: Date) async throws -> [StoredCheckIn] {
        lock.withLock { _reads += 1 }
        if readHangs { try await Task.sleep(for: .seconds(30)) }
        if readFails { throw URLError(.notConnectedToInternet) }
        return existing
    }

    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn {
        lock.withLock { _writes.append(draft) }
        if writeHangs { try await Task.sleep(for: .seconds(30)) }
        if writeFails { throw URLError(.notConnectedToInternet) }
        return StoredCheckIn(
            id: writes.count, ledger: draft.key.ledger, label: draft.key.label,
            form: draft.key.form, mg: draft.key.mg, quantity: draft.quantity
        )
    }
}

private func key(_ id: Int, mg: Double = 3, label: String = "Pouches") -> StoredPadKey {
    StoredPadKey(id: id, form: .pouch, label: label, mg: mg, position: 0, ndc: nil)
}

/// Covers reading today, and folding a pending tap into its tally.
@MainActor
struct TodayRecordTests {
    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func record(_ store: FakeCheckIns) -> TodayRecord {
        TodayRecord(store: store, day: { self.day })
    }

    /// A record whose idea of "now" the test can move, for the day that turns
    /// over while the app is still open.
    private func record(_ store: FakeCheckIns, clock: Clock) -> TodayRecord {
        TodayRecord(store: store, day: { clock.now })
    }

    /// A movable clock. A class so the record's closure sees the change.
    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    @Test("today is read into the tally, and a pending tap is folded on top")
    func theTallyIsBuiltFromBoth() async {
        let store = FakeCheckIns()
        store.existing = [
            StoredCheckIn(id: 1, ledger: .source, label: "Pouches", form: .pouch, mg: 3, quantity: 2)
        ]
        let record = record(store)

        await record.load()
        record.selection.tap(key(9, mg: 1.5))

        let tally = record.tally(ceilingMg: 12)
        #expect(tally.loggedMg == 6, "what was already on the day did not reach the tally")
        #expect(tally.pendingMg == 1.5)
        #expect(tally.projectedMg == 7.5)
    }

    @Test("a day that cannot be read is not an empty day")
    func aFailedReadIsNotAnEmptyDay() async {
        // Showing "nothing logged yet" over a failed read invites somebody to
        // log a second time against a day the app could not see.
        let store = FakeCheckIns()
        store.readFails = true
        let record = record(store)

        await record.load()

        guard case let .unavailable(message) = record.status else {
            Issue.record("a failed read did not reach the unavailable state")
            return
        }
        #expect(message.contains("try again"))
        #expect(!message.contains("URLError"))
    }

    @Test("a build with no backend says so rather than blaming the connection")
    func aMissingBackendIsItsOwnSentence() async {
        let record = TodayRecord(store: nil, day: { self.day })

        await record.load()

        guard case let .unavailable(message) = record.status else {
            Issue.record("a build with no backend did not report the day unavailable")
            return
        }
        #expect(message.contains("no backend"))
        #expect(!message.contains("connection"))
    }

    @Test("a second read does not start while the first is in flight")
    func concurrentLoadsAreSerialised() async {
        // The screen's `task` and a pull-to-refresh can both fire, and a stale
        // failure landing after a fresh success would put the error back in
        // front of somebody whose day had just arrived.
        let store = FakeCheckIns()
        store.readHangs = true
        let record = record(store)

        let first = Task { await record.load() }

        await waitUntil { store.reads == 1 }

        await record.load()

        #expect(store.reads == 1, "a second read started while the first was in flight")
        first.cancel()
        await first.value

        // What the cancelled load left behind, which the earlier version of
        // this test never looked at. Two regressions hid in that gap: reporting
        // an abandoned read as a failure, and leaving the guard latched so no
        // read could ever start again.
        #expect(record.status == .loading, "an abandoned read reported something")

        store.readHangs = false
        await record.load()
        #expect(store.reads == 2, "the guard stayed latched after the first read was abandoned")
        #expect(record.status == .ready)
    }

    // MARK: - The day turning over

    @Test("yesterday's entries stop counting the moment the date turns")
    func midnightIsNotSomethingToSleepThrough() async {
        // A record that outlives midnight holds rows belonging to yesterday.
        // Measuring them against today's ceiling reports a day nobody has had
        // yet — and on the last week of a taper, where the cap is small, it
        // reports one somebody has already blown before waking up.
        let store = FakeCheckIns()
        store.existing = [
            StoredCheckIn(id: 1, ledger: .source, label: "Pouches", form: .pouch, mg: 3, quantity: 4)
        ]
        let clock = Clock(day)
        let record = record(store, clock: clock)
        await record.load()
        #expect(record.tally(ceilingMg: 12).loggedMg == 12, "the fixture must start with a full day")

        clock.now = day.addingTimeInterval(86_400)

        #expect(record.hasRolledOver)
        #expect(record.entries.isEmpty, "yesterday's rows were still being served as today's")
        #expect(record.tally(ceilingMg: 12).loggedMg == 0, "yesterday was counted against today's cap")
    }

    @Test("twenty minutes across midnight is a rollover; twenty hours inside a day is not")
    func theBoundaryIsTheDateAndNotTheDuration() async {
        // The case a duration cannot express, and the one people actually hit:
        // logging at ten to midnight and looking again at ten past. Twenty
        // minutes have passed and the day is gone. The mirror matters as much —
        // a long single day must not roll over just because hours have piled
        // up, or a morning's entries vanish at bedtime.
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.timeZone = zone

        func at(_ hour: Int, _ minute: Int, day: Int) -> Date {
            calendar.date(from: DateComponents(
                timeZone: zone, year: 2025, month: 10, day: day, hour: hour, minute: minute
            ))!
        }

        let clock = Clock(at(23, 50, day: 9))
        let store = FakeCheckIns()
        let record = TodayRecord(store: store, calendar: calendar, day: { clock.now })
        await record.load()

        clock.now = at(0, 10, day: 10)
        #expect(record.hasRolledOver, "twenty minutes across midnight is a new day")

        // And the other way: a whole day is still one day.
        let longDay = Clock(at(0, 5, day: 9))
        let steady = TodayRecord(store: FakeCheckIns(), calendar: calendar, day: { longDay.now })
        await steady.load()
        longDay.now = at(23, 55, day: 9)
        #expect(!steady.hasRolledOver, "almost twenty-four hours inside one day is not a rollover")
    }

    @Test("a record that has never read anything has not rolled over")
    func nothingLoadedIsNotStale() {
        // Otherwise the very first render would report a rollover before there
        // was a day to roll over from.
        #expect(!record(FakeCheckIns()).hasRolledOver)
    }

    @Test("re-reading on the new day settles it")
    func aReloadPutsTheRecordBackOnToday() async {
        let store = FakeCheckIns()
        store.existing = [
            StoredCheckIn(id: 1, ledger: .source, label: "Pouches", form: .pouch, mg: 3, quantity: 4)
        ]
        let clock = Clock(day)
        let record = record(store, clock: clock)
        await record.load()
        clock.now = day.addingTimeInterval(86_400)

        store.existing = [
            StoredCheckIn(id: 2, ledger: .source, label: "Pouches", form: .pouch, mg: 3, quantity: 1)
        ]
        await record.load()

        #expect(!record.hasRolledOver)
        #expect(record.tally(ceilingMg: 12).loggedMg == 3, "the new day's rows did not take over")
    }

    /// Waits, briefly, for something to become true.
    ///
    /// Bounded on purpose: an unbounded wait turns a regression in the code
    /// under test into a suite that hangs rather than one that fails.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { await Task.yield() }
        #expect(condition(), "the condition never became true")
    }

    // MARK: - Writing

    @Test("checking in logs what was selected and adds it to today")
    func aCheckInLandsOnTheDay() async {
        let store = FakeCheckIns()
        let record = record(store)
        await record.load()
        record.selection.tap(key(1))
        record.selection.tap(key(1))

        await record.checkIn()

        #expect(store.writes.count == 1)
        #expect(store.writes.first?.quantity == 2, "the count was not carried into the write")
        #expect(store.writes.first?.day == day, "the entry was dated from somewhere other than the record's day")
        #expect(record.entries.count == 1, "the entry did not reach today")
        #expect(record.selection.pending == nil, "the selection survived a successful write")
    }

    @Test("the day is not re-read to learn what we were just told")
    func aWriteDoesNotCostAReload() async {
        // The row that comes back is the row that was written. A second round
        // trip would put a spinner between the tap and the total, on the one
        // interaction the whole app is built around.
        let store = FakeCheckIns()
        let record = record(store)
        await record.load()
        record.selection.tap(key(1))

        await record.checkIn()

        #expect(store.reads == 1, "the day was re-read after a write")
    }

    @Test("checking in with nothing selected writes nothing")
    func anEmptyCheckInIsNotAWrite() async {
        let store = FakeCheckIns()
        let record = record(store)

        await record.checkIn()

        #expect(store.writes.isEmpty)
    }

    @Test("a write that fails keeps the selection for the retry")
    func aFailedWriteHoldsOntoWhatWasTapped() async {
        // Clearing it would make somebody re-tap a count they had already
        // tapped out, on the attempt right after one that failed.
        let store = FakeCheckIns()
        store.writeFails = true
        let record = record(store)
        record.selection.tap(key(1))
        record.selection.tap(key(1))

        await record.checkIn()

        #expect(record.selection.pending?.quantity == 2, "the selection was thrown away")
        #expect(record.writeFailure?.contains("try again") == true)
        #expect(!(record.writeFailure?.contains("URLError") ?? false))
        #expect(record.entries.isEmpty, "a failed write reached the day anyway")
    }

    @Test("a retry that works clears the failure")
    func aFailureDoesNotOutliveItsCause() async {
        // Asserting the exit from the state, not only the entry.
        let store = FakeCheckIns()
        store.writeFails = true
        let record = record(store)
        record.selection.tap(key(1))
        await record.checkIn()
        #expect(record.writeFailure != nil)

        store.writeFails = false
        await record.checkIn()

        #expect(record.writeFailure == nil)
        #expect(record.entries.count == 1)
        #expect(store.writes.count == 2, "the retry re-sent what was still selected")
    }

    @Test("clearing also clears a failure it is no longer about")
    func clearingSilencesAStaleFailure() async {
        let store = FakeCheckIns()
        store.writeFails = true
        let record = record(store)
        record.selection.tap(key(1))
        await record.checkIn()

        record.clear()

        #expect(record.writeFailure == nil, "a message about a write nobody is attempting")
        #expect(record.selection.pending == nil)
    }

    @Test("a build with no backend says nothing can be logged")
    func aMissingBackendCannotWriteEither() async {
        let record = TodayRecord(store: nil, day: { self.day })
        record.selection.tap(key(1))

        await record.checkIn()

        #expect(record.writeFailure?.contains("no backend") == true)
        #expect(!(record.writeFailure?.contains("connection") ?? false))
    }

    @Test("a tap that crosses midnight starts the new day rather than joining the old one")
    func aWriteAfterRolloverDoesNotJoinYesterday() async {
        // The screen can be open across midnight with yesterday's rows behind
        // it. The write lands on the new day — so the total beside it has to be
        // the new day's too, or the first entry of the morning is added to a
        // day that ended hours ago.
        let store = FakeCheckIns()
        store.existing = [
            StoredCheckIn(id: 1, ledger: .source, label: "Pouches", form: .pouch, mg: 3, quantity: 4)
        ]
        let clock = Clock(day)
        let record = record(store, clock: clock)
        await record.load()
        #expect(record.tally(ceilingMg: 12).loggedMg == 12)

        clock.now = day.addingTimeInterval(86_400)
        record.selection.tap(key(1, mg: 3))
        await record.checkIn()

        #expect(!record.hasRolledOver, "the record stayed on the day it just wrote past")
        #expect(record.entries.count == 1, "yesterday's rows were carried into the new day")
        #expect(record.tally(ceilingMg: 12).loggedMg == 3)
    }

    @Test("a write abandoned mid-flight reports nothing and keeps the selection")
    func aCancelledWriteIsNotAFailure() async {
        // Navigating away is not a refusal. It is not a success either — the
        // row may or may not have landed, so the day is left as it was and the
        // next load settles it.
        let store = FakeCheckIns()
        store.writeHangs = true
        let record = record(store)
        record.selection.tap(key(1))

        let task = Task { await record.checkIn() }
        await waitUntil { store.writes.count == 1 }
        task.cancel()
        await task.value

        #expect(record.writeFailure == nil, "an abandoned write was reported as a failure")
        #expect(record.selection.pending != nil, "the selection was cleared by a cancellation")
        #expect(record.entries.isEmpty, "an unconfirmed row was added to the day")
    }

    @Test("a second check-in does not start while the first is in flight")
    func concurrentWritesAreSerialised() async {
        // The button is disabled while saving, but a disabled button is a
        // rendering decision and this is the rule. Two taps either side of the
        // first render would otherwise log the same thing twice.
        let store = FakeCheckIns()
        store.writeHangs = true
        let record = record(store)
        record.selection.tap(key(1))

        let first = Task { await record.checkIn() }
        await waitUntil { store.writes.count == 1 }

        await record.checkIn()
        #expect(store.writes.count == 1, "a second write started while the first was in flight")

        first.cancel()
        await first.value

        // And the guard is released rather than latched, so a retry can run.
        store.writeHangs = false
        await record.checkIn()
        #expect(store.writes.count == 2, "the guard stayed latched after the first write was abandoned")
    }
}
