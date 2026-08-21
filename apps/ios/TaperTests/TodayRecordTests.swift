import Foundation
import Testing
@testable import Taper

/// A check-in store that does what the test needs and counts what it was asked.
private final class FakeCheckIns: CheckInStoring, @unchecked Sendable {
    var existing: [StoredCheckIn] = []
    var readFails = false
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

        // Bounded, because an unbounded wait turns a regression here into a
        // suite that hangs rather than one that fails.
        let deadline = Date().addingTimeInterval(2)
        while store.reads == 0, Date() < deadline {
            await Task.yield()
        }
        #expect(store.reads == 1, "the first read never started")

        await record.load()

        #expect(store.reads == 1, "a second read started while the first was in flight")
        first.cancel()
        await first.value
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

    @Test("a later hour of the same day is not a rollover")
    func theDayDoesNotTurnAtEveryTick() {
        // The check is a calendar day, not an elapsed interval. Reading it as
        // "more than a few hours" would drop a morning's entries at lunchtime.
        let store = FakeCheckIns()
        let clock = Clock(day)
        let record = record(store, clock: clock)

        clock.now = day.addingTimeInterval(60 * 60)

        #expect(!record.hasRolledOver)
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
}
