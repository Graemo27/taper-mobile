import Foundation
import Testing
@testable import Taper

/// A check-in store that does what the test needs and counts what it was asked.
private final class FakeCheckIns: CheckInStoring, @unchecked Sendable {
    var existing: [StoredCheckIn] = []
    var readFails = false
    var writeFails = false
    var removeFails = false
    /// Holds a removal open, so a reload can land while one is in flight.
    var removeDelay: Duration?
    /// A brief, finite delay — long enough to interrupt during, short enough
    /// to finish. Finite on purpose: the write cannot be cancelled, so a fake
    /// that never returns would hang the suite rather than test it.
    var writeDelay: Duration?
    /// Holds a read open, so a second can be attempted while the first is in
    /// flight.
    var readHangs = false
    /// Holds a read open for a fixed spell, so a removal can settle while the
    /// read is still in flight and the read answers from before it.
    var readDelay: Duration?

    private let lock = NSLock()
    private var _writes: [CheckInDraft] = []
    private var _reads = 0
    /// Every draft it was asked to log, in order. Drafts rather than a count,
    /// so a retry sending a different quantity is distinguishable from a repeat.
    var writes: [CheckInDraft] { lock.withLock { _writes } }
    var reads: Int { lock.withLock { _reads } }

    func entries(on day: Date) async throws -> [StoredCheckIn] {
        lock.withLock { _reads += 1 }
        if let readDelay { try await Task.sleep(for: readDelay) }
        if readHangs { try await Task.sleep(for: .seconds(30)) }
        if readFails { throw URLError(.notConnectedToInternet) }
        return existing
    }

    private var _removed: [Int] = []
    /// Every id it was asked to remove, in order.
    var removed: [Int] { lock.withLock { _removed } }

    func remove(_ id: Int) async throws {
        lock.withLock { _removed.append(id) }
        if let removeDelay { try await Task.sleep(for: removeDelay) }
        if removeFails { throw URLError(.notConnectedToInternet) }
    }

    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn {
        lock.withLock { _writes.append(draft) }
        // `try`, not `try?`. Swallowing the cancellation here would let the
        // write finish either way, and the test that asks whether it can be
        // abandoned would pass against code that abandons it.
        if let writeDelay { try await Task.sleep(for: writeDelay) }
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

    @Test("a screen going away does not drop the tap that was already made")
    func aWriteIsNotAbandonedByItsCaller() async {
        // The state this removes rather than handles. If a write could be
        // abandoned after the insert commits, the retry would write it again —
        // `check_ins` has nothing unique to conflict on, and content cannot
        // tell a duplicate from a second genuine tap, because two 3 mg pouches
        // half a minute apart is an ordinary afternoon.
        //
        // So the write finishes. A tap somebody made is recorded.
        let store = FakeCheckIns()
        store.writeDelay = .milliseconds(120)
        let record = record(store)
        record.selection.tap(key(1))

        let task = Task { await record.checkIn() }
        await waitUntil { store.writes.count == 1 }
        task.cancel()
        await task.value

        #expect(store.writes.count == 1)
        #expect(record.entries.count == 1, "the tap was dropped when its caller went away")
        #expect(record.selection.pending == nil, "a completed write left the selection behind")
        #expect(record.writeFailure == nil, "a completed write was reported as a failure")
    }

    @Test("and the retry after it does not write a second row")
    func theRetryAfterAnInterruptedWriteIsNotADuplicate() async {
        // The consequence, stated as its own assertion: with nothing left
        // pending, a second tap on the button has nothing to send. That is what
        // makes the missing idempotency key survivable.
        let store = FakeCheckIns()
        store.writeDelay = .milliseconds(120)
        let record = record(store)
        record.selection.tap(key(1))

        let task = Task { await record.checkIn() }
        await waitUntil { store.writes.count == 1 }
        task.cancel()
        await task.value

        await record.checkIn()

        #expect(store.writes.count == 1, "the interrupted write was sent a second time")
        #expect(record.entries.count == 1)
    }

    @Test("a second check-in does not start while the first is in flight")
    func concurrentWritesAreSerialised() async {
        // The button is disabled while saving, but a disabled button is a
        // rendering decision and this is the rule. Two taps either side of the
        // first render would otherwise log the same thing twice.
        //
        // The first write is left to finish rather than cancelled, because it
        // can no longer be cancelled — so the guard has to be seen releasing on
        // its own.
        let store = FakeCheckIns()
        store.writeDelay = .milliseconds(150)
        let record = record(store)
        record.selection.tap(key(1))

        let first = Task { await record.checkIn() }
        await waitUntil { store.writes.count == 1 }

        await record.checkIn()
        #expect(store.writes.count == 1, "a second write started while the first was in flight")

        await first.value

        // Released rather than latched: a fresh selection can still be logged.
        record.selection.tap(key(1))
        await record.checkIn()
        #expect(store.writes.count == 2, "the guard stayed latched after the first write finished")
    }

    // MARK: - What the button says and whether it can be pressed

    @Test("the button names what would be logged, not how many taps")
    func theButtonCarriesThePendingTotal() {
        // The number that matters is the one going against the cap. Three
        // pouches at 3 mg is 9 going onto the day, and "× 3" is the count the
        // readout already shows above the meter.
        let record = record(FakeCheckIns())
        record.selection.tap(key(1, mg: 3))
        record.selection.tap(key(1, mg: 3))
        record.selection.tap(key(1, mg: 3))

        #expect(record.checkInTitle == "Check in · 9 mg")
    }

    @Test("with nothing selected the button says so and cannot be pressed")
    func nothingToLogIsNotAnAction() {
        let record = record(FakeCheckIns())

        #expect(record.checkInTitle == "Check in")
        #expect(!record.canCheckIn)
    }

    @Test("the button is dead while a write is in flight")
    func theButtonCannotBePressedTwice() async {
        // The guard in `checkIn()` is what actually prevents the second write.
        // This is the rule the screen reads to *show* that, and the two must
        // agree — a live-looking button over a guard that refuses is a tap that
        // does nothing, which people press again.
        // A short delay rather than a long one: the write is deliberately not
        // cancellable, so a thirty-second hang would be thirty seconds of
        // suite rather than a test.
        let store = FakeCheckIns()
        store.writeDelay = .milliseconds(200)
        let record = record(store)
        record.selection.tap(key(1))
        #expect(record.canCheckIn)

        let first = Task { await record.checkIn() }
        await waitUntil { store.writes.count == 1 }

        #expect(!record.canCheckIn, "the button stayed live over a guard that would refuse")

        await first.value
        #expect(record.entries.count == 1, "the write did not finish")
    }

    @Test("the button comes back once the write is done")
    func theButtonIsNotDeadForever() async {
        let store = FakeCheckIns()
        let record = record(store)
        record.selection.tap(key(1))

        await record.checkIn()

        // Nothing selected any more, so it is off for that reason rather than
        // because the guard stayed latched — which the next tap proves.
        #expect(!record.canCheckIn)
        record.selection.tap(key(2))
        #expect(record.canCheckIn)
    }

    // MARK: - Taking one back

    private func logged(_ id: Int, mg: Double, quantity: Int = 1) -> StoredCheckIn {
        StoredCheckIn(id: id, ledger: .source, label: "Pouches",
                      form: .pouch, mg: mg, quantity: quantity)
    }

    @Test("removing an entry takes it off the day and off the server")
    func aMistapCanBeTakenBack() async {
        // A log nobody can correct is one people stop trusting, and a mis-tap
        // that permanently distorts the cap is worse than no record at all.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3), logged(2, mg: 6)]
        let record = record(store)
        await record.load()

        await record.remove(logged(2, mg: 6))

        #expect(store.removed == [2], "the wrong entry was removed, or none was")
        #expect(record.entries.map(\.id) == [1])
        #expect(record.tally(ceilingMg: 12).loggedMg == 3, "the cap still counted what was removed")
    }

    @Test("the row leaves the day before the server is asked")
    func removingDoesNotWaitToLookLikeItWorked() async {
        // The commonest reason to delete is having just tapped the wrong key.
        // Waiting on a round trip before the row goes makes correcting it feel
        // like it might not have worked, which is when people tap again.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3)]
        let record = record(store)
        await record.load()

        let removing = Task { await record.remove(self.logged(1, mg: 3)) }
        await waitUntil { store.removed == [1] }
        #expect(record.entries.isEmpty, "the row was still on the day while the request was open")

        await removing.value
    }

    @Test("a removal that fails puts the entry back where it was")
    func aFailedRemovalIsNotSilent() async {
        // Optimistic and then wrong is worse than slow: somebody who believes
        // an entry is gone will not go looking for it again, and the cap would
        // disagree with the log for the rest of the day.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3), logged(2, mg: 6), logged(3, mg: 1.5)]
        store.removeFails = true
        let record = record(store)
        await record.load()

        await record.remove(logged(2, mg: 6))

        #expect(record.entries.map(\.id) == [1, 2, 3], "the entry came back in the wrong place")
        #expect(record.removeFailure?.contains("try again") == true)
        #expect(!(record.removeFailure?.contains("URLError") ?? false))
    }

    @Test("removing something that is not on the day does nothing")
    func aStaleRowIsNotSentToTheServer() async {
        // Two screens can be open on the same day. A delete issued against a
        // row another one already removed should not be sent again — the id is
        // gone, and the request would report a failure about nothing.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3)]
        let record = record(store)
        await record.load()

        await record.remove(logged(99, mg: 3))

        #expect(store.removed.isEmpty)
        #expect(record.entries.count == 1)
    }

    @Test("the day reads back as a count and a total")
    func theSummaryNamesBothNumbers() async {
        // The count includes treatment and the milligrams do not, which is why
        // the two can look unrelated. The list shows what happened; the cap
        // counts what is being tapered off.
        let store = FakeCheckIns()
        store.existing = [
            logged(1, mg: 3),
            logged(2, mg: 4.5),
            StoredCheckIn(id: 3, ledger: .treatment, label: "Patch",
                          form: .patch, mg: 14, quantity: 1),
        ]
        let record = record(store)
        await record.load()

        #expect(record.summary(ceilingMg: 12) == "3 check-ins · 7.5 of 12 mg")
    }

    @Test("the summary reports what happened, not what is about to")
    func aPendingTapIsNotACheckIn() async {
        // The meter above shows where a tap would leave the day. This line is
        // a statement about the day itself, and counting a selection here
        // would tell somebody they had logged something they have not — on the
        // one screen whose whole job is to say what is on the record.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3)]
        let record = record(store)
        await record.load()

        record.selection.tap(key(9, mg: 4.5))

        #expect(record.summary(ceilingMg: 12) == "1 check-in · 3 of 12 mg")
    }

    @Test("one check-in is not plural")
    func theSummaryCountsInEnglish() async {
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3)]
        let record = record(store)
        await record.load()

        #expect(record.summary(ceilingMg: 12) == "1 check-in · 3 of 12 mg")
    }

    @Test("a reload during a removal does not put the row back")
    func aReloadCannotUndoACorrection() async {
        // The day is read from the server, which still holds the row until the
        // delete commits. Without excluding it, a reload landing mid-removal
        // puts the entry back on screen in front of the person who has just
        // taken it off — and then the delete succeeds, so the screen and the
        // server disagree until something else reloads.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3), logged(2, mg: 6)]
        store.removeDelay = .milliseconds(200)
        let record = record(store)
        await record.load()

        let removing = Task { await record.remove(self.logged(2, mg: 6)) }
        await waitUntil { store.removed == [2] }
        await record.load()

        #expect(record.entries.map(\.id) == [1], "the reload resurrected a row being removed")
        await removing.value
        #expect(record.entries.map(\.id) == [1])
    }

    @Test("a reload during a removal that fails leaves one row, not two")
    func aFailedRemovalDoesNotDoubleAfterAReload() async {
        // The other half. The reload already contains the entry, and the
        // failure path puts it back — so without the exclusion the day ends up
        // holding it twice, and the cap counts it twice with it.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3), logged(2, mg: 6)]
        store.removeDelay = .milliseconds(200)
        store.removeFails = true
        let record = record(store)
        await record.load()

        let removing = Task { await record.remove(self.logged(2, mg: 6)) }
        await waitUntil { store.removed == [2] }
        await record.load()
        await removing.value

        #expect(record.entries.map(\.id) == [1, 2], "the entry came back twice, or in the wrong order")
        #expect(record.tally(ceilingMg: 24).loggedMg == 9, "the cap counted a restored row twice")
    }

    @Test("a failed removal is not restored into a day it did not come from")
    func aFailedRemovalDoesNotCrossMidnight() async {
        // Midnight during the request, and a reload that lands on the far side
        // of it. Putting the entry back now would file yesterday's row under
        // today and charge today's cap for it — the exact thing rollover
        // exists to prevent, arriving through the one path that writes to the
        // day without reading the clock.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3), logged(2, mg: 6)]
        store.removeDelay = .milliseconds(200)
        store.removeFails = true
        let clock = Clock(day)
        let record = record(store, clock: clock)
        await record.load()

        let removing = Task { await record.remove(self.logged(2, mg: 6)) }
        await waitUntil { store.removed == [2] }
        clock.now = day.addingTimeInterval(86_400)
        store.existing = [logged(7, mg: 4.5)]
        await record.load()
        await removing.value

        #expect(record.entries.map(\.id) == [7], "yesterday's entry was restored into today")
        #expect(record.tally(ceilingMg: 24).loggedMg == 4.5, "today's cap counted yesterday's row")
        #expect(record.removeFailure != nil, "a removal that failed said nothing")
    }

    @Test("a read that predates a delete does not put the row back")
    func aStaleReadCannotResurrectARemovedRow() async {
        // The other end of the same race. `removing` says what is in flight
        // now, and a read that started before the delete and lands after it
        // finds the set already empty — so the pre-delete snapshot it is
        // holding goes straight onto the day, and the row somebody removed is
        // back with its milligrams.
        let store = FakeCheckIns()
        store.existing = [logged(1, mg: 3), logged(2, mg: 6)]
        let record = record(store)
        await record.load()

        store.readDelay = .milliseconds(300)
        let reloading = Task { await record.load() }
        await waitUntil { store.reads == 2 }
        // Settles while that read is still open. `existing` is left alone on
        // purpose: it is what the server hands back to a read taken before the
        // delete committed.
        await record.remove(logged(2, mg: 6))
        await reloading.value

        #expect(record.entries.map(\.id) == [1], "a read from before the delete put the row back")
        #expect(record.tally(ceilingMg: 24).loggedMg == 3, "the cap counted a row that was removed")
        #expect(record.status == .ready, "the day was left on a spinner")
    }
}
