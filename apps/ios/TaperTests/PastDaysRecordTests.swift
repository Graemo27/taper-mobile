import Foundation
import Testing
@testable import Taper

/// A day's check-ins, and a count of how often they were asked for.
private final class FakeDays: CheckInReading, @unchecked Sendable {
    var byDay: [String: [StoredCheckIn]] = [:]
    var fails = false
    /// Holds a read open, so the day can turn while one is in flight.
    var delay: Duration?
    private let lock = NSLock()
    private var _asked: [String] = []
    /// Every day it was asked about, in order.
    var asked: [String] { lock.withLock { _asked } }

    private let calendar: Calendar
    init(calendar: Calendar) { self.calendar = calendar }

    func entries(from first: Date, to last: Date) async throws -> [StoredCheckIn] {
        // Records the span it was handed, so a test can tell one request for a
        // week from seven requests for a day.
        let from = PlanDay.wireFormat(first, timeZone: calendar.timeZone)
        let to = PlanDay.wireFormat(last, timeZone: calendar.timeZone)
        lock.withLock { _asked.append(from == to ? from : "\(from)…\(to)") }
        if let delay { try await Task.sleep(for: delay) }
        if fails { throw URLError(.notConnectedToInternet) }

        var days: [String] = []
        var cursor = calendar.startOfDay(for: min(first, last))
        let end = calendar.startOfDay(for: max(first, last))
        while cursor <= end {
            days.append(PlanDay.wireFormat(cursor, timeZone: calendar.timeZone))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        // Stamped with the day they are filed under, because that is what the
        // server does: `logged_on` is a column, and the record groups a span by
        // it. A fake that left it unset would hand back a week of rows that
        // belong to no day in it.
        return days.flatMap { key in (byDay[key] ?? []).map { $0.loggedOn(key) } }
    }
}

private extension StoredCheckIn {
    /// The same entry, filed under a given day.
    func loggedOn(_ wire: String) -> StoredCheckIn {
        StoredCheckIn(id: id, ledger: ledger, label: label, form: form,
                      mg: mg, quantity: quantity, loggedOn: wire, createdAt: createdAt)
    }
}

private final class FakeVersions: PlanVersionReading, @unchecked Sendable {
    var versions: [StoredPlanVersion] = []
    func versions() async throws -> [StoredPlanVersion] { versions }
}

/// Covers the run of days the log draws under today: how the window is built,
/// and the three ways it has been caught serving a day that is no longer in it.
@MainActor
struct PastDaysRecordTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var anchor: Date { Date(timeIntervalSince1970: 1_780_000_000) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: anchor))!
    }

    private func wire(_ offset: Int) -> String {
        PlanDay.wireFormat(day(offset), timeZone: calendar.timeZone)
    }

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func entry(_ id: Int, mg: Double) -> StoredCheckIn {
        StoredCheckIn(id: id, ledger: .source, label: "Pouch", form: .pouch,
                      mg: mg, quantity: 1, loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { await Task.yield() }
        #expect(condition(), "the condition never became true")
    }

    private func version(
        from offset: Int, startingCap: Double = 18, currentCap: Double = 18, quitAfter: Int? = nil
    ) -> StoredPlanVersion {
        StoredPlanVersion(
            effectiveFrom: wire(offset),
            startingCapMg: startingCap,
            currentCapMg: currentCap,
            quitDate: quitAfter.map { wire($0) },
            firstUseMinutes: 20,
            sickInBed: true
        )
    }

    private func record(_ days: FakeDays, _ plans: FakeVersions, clock: Clock) -> PastDaysRecord {
        PastDaysRecord(checkIns: days, plans: plans, calendar: calendar, today: { clock.now })
    }

    @Test("yesterday is read against the cap that was in force on it")
    func theDayIsMeasuredByItsOwnPlan() async {
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3), entry(2, mg: 3)]
        let plans = FakeVersions()
        plans.versions = [StoredPlanVersion(
            effectiveFrom: wire(-30), startingCapMg: 18, currentCapMg: 12,
            quitDate: nil, firstUseMinutes: 20, sickInBed: true
        )]
        let record = record(days, plans, clock: Clock(day(0)))

        await record.load()

        #expect(record.rollups.first?.loggedMg == 6)
        #expect(record.rollups.first?.capMg == 12, "yesterday was not measured against its own plan")
        // One request for the whole window, not one per day. Seven round trips
        // would report a week as seven separate successes and failures.
        #expect(days.asked == ["\(wire(-7))…\(wire(-1))"], "it did not read the window in one go")
    }

    @Test("a window that finishes after midnight is not published as yesterday")
    func aReadOutlivedByTheDayItAskedFor() async {
        // The window is chosen before two awaits and assigned after them. A
        // read that starts at 23:59 and lands at 00:01 is answering for a day
        // that is no longer yesterday, and publishing it would put the day
        // before last under the heading — the same lie the cache key and the
        // failure path each close by another door.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.delay = .milliseconds(200)
        let clock = Clock(day(0))
        let record = record(days, FakeVersions(), clock: clock)

        let loading = Task { await record.load() }
        await waitUntil { !days.asked.isEmpty }
        clock.now = day(1)
        await loading.value

        #expect(record.rollups.isEmpty, "a window for a day that had passed was published")

        // And the record has forgotten it, so coming back reads the new day
        // rather than short-circuiting on a claim it no longer honours.
        days.delay = nil
        days.byDay[wire(0)] = [entry(2, mg: 9)]
        await record.load()
        #expect(record.rollups.first?.loggedMg == 9, "the record would not re-read the new day")
    }

    @Test("a slow read does not overwrite the window that overtook it")
    func theOlderAnswerLosesEvenWhenItArrivesLast() async {
        // Two loads in flight, the older finishing last. Without the check it
        // would overwrite a correct window with a stale one *and* leave the
        // cache claiming the new day — so every later load would short-circuit
        // and the wrong week would stay on screen for good.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.byDay[wire(0)] = [entry(2, mg: 9)]
        days.delay = .milliseconds(250)
        let clock = Clock(day(0))
        let record = record(days, FakeVersions(), clock: clock)

        let slow = Task { await record.load() }
        await waitUntil { !days.asked.isEmpty }

        // Midnight, and a second load that beats the first home.
        clock.now = day(1)
        days.delay = nil
        await record.load()
        #expect(record.rollups.first?.loggedMg == 9)

        await slow.value
        #expect(record.rollups.first?.loggedMg == 9, "the older window overwrote the newer one")
    }

    @Test("a stale read that fails does not tear down the window that beat it")
    func anOvertakenFailureIsNotEveryonesFailure() async {
        // The worse half of the interleaving. A read started before midnight
        // fails after a newer read has already loaded the day correctly — and
        // an unguarded catch would clear the good window, forget the cache and
        // put an apology on screen for a request nobody was waiting on.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.byDay[wire(0)] = [entry(2, mg: 9)]
        days.delay = .milliseconds(250)
        let clock = Clock(day(0))
        let record = record(days, FakeVersions(), clock: clock)

        let slow = Task { await record.load() }
        await waitUntil { !days.asked.isEmpty }

        // Midnight, and a load that overtakes the first and succeeds.
        clock.now = day(1)
        days.delay = nil
        await record.load()
        #expect(record.rollups.first?.loggedMg == 9)

        // Only now does the older read wake up — and throw.
        days.fails = true
        await slow.value

        #expect(record.rollups.first?.loggedMg == 9, "a superseded failure cleared the good window")
        #expect(!record.isUnavailable, "a superseded failure put an apology on screen")

        // And the cache is intact, so returning to the log does not re-read a
        // day it already has.
        let reads = days.asked.count
        await record.load()
        #expect(days.asked.count == reads, "the superseded failure forgot a window that was fine")
    }

    @Test("asking for earlier reaches further back without losing what it had")
    func theWindowGrowsFromTheSameEnd() async {
        // The extension keeps the same end and reaches further, so a cache keyed
        // on the end day alone would refuse it as already loaded. That is the
        // reason the key is the whole window and not just its last day.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.byDay[wire(-9)] = [entry(2, mg: 6)]
        let versions = FakeVersions()
        versions.versions = [version(from: -60)]
        let record = record(days, versions, clock: Clock(day(0)))

        await record.load()
        #expect(record.rollups.count == 7)
        #expect(record.rollups.contains { $0.loggedMg == 6 } == false, "day -9 is outside the week")

        await record.showEarlier()

        #expect(record.rollups.count == 14, "the window did not grow")
        #expect(record.rollups.first?.day == day(-1), "the window moved instead of reaching back")
        #expect(record.rollups.contains { $0.loggedMg == 6 }, "the older day was not picked up")
        #expect(record.rollups.contains { $0.loggedMg == 3 }, "the days it already had were lost")
    }

    @Test("there is nothing earlier to offer once the window reaches day one")
    func theOfferStopsAtTheStartOfTheTaper() async {
        // Days before the taper began have no ceiling — every one would draw as
        // a day nobody was measuring. Offering to load them would be the app
        // volunteering to fill the screen with nothing.
        let days = FakeDays(calendar: calendar)
        let versions = FakeVersions()
        versions.versions = [version(from: -5)]
        let shallow = record(days, versions, clock: Clock(day(0)))

        await shallow.load()

        #expect(!shallow.hasEarlier, "it offered days from before the plan existed")

        // And a taper that began well before the window still has more to show.
        let older = FakeVersions()
        older.versions = [version(from: -60)]
        let deep = record(FakeDays(calendar: calendar), older, clock: Clock(day(0)))
        await deep.load()
        #expect(deep.hasEarlier)
    }

    @Test("a second press while one is in flight does not stack the window")
    func showEarlierIsNotPressedTwice() async {
        // Two presses landing together would add two weeks and fire two reads
        // for windows that disagree — the same overtaking problem, this time
        // caused by a finger rather than by midnight.
        let days = FakeDays(calendar: calendar)
        days.delay = .milliseconds(200)
        let versions = FakeVersions()
        versions.versions = [version(from: -60)]
        let record = record(days, versions, clock: Clock(day(0)))
        await record.load()

        let first = Task { await record.showEarlier() }
        await waitUntil { record.isLoadingEarlier }
        await record.showEarlier()
        await first.value

        #expect(record.rollups.count == 14, "a second press stacked another week on")
    }

    @Test("a week is seven days, including the ones with nothing on them")
    func anEmptyDayStillGetsItsPlace() async {
        // Built from the calendar rather than from the rows. A week with two
        // quiet days drawn as five would read as a shorter week — and the quiet
        // days are the ones somebody most wants to see, because they are the
        // evidence the taper is working.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.byDay[wire(-4)] = [entry(2, mg: 6)]
        let record = record(days, FakeVersions(), clock: Clock(day(0)))

        await record.load()

        #expect(record.rollups.count == 7, "the window lost the days with nothing on them")
        #expect(record.rollups.map(\.loggedMg) == [3, 0, 0, 6, 0, 0, 0])
        // Newest first, which is the order the log draws them.
        #expect(record.rollups.first?.day == day(-1))
        #expect(record.rollups.last?.day == day(-7))
    }

    @Test("each day in the window is measured against its own cap")
    func theWindowIsNotOneCapRepeated() async {
        // The reason the plan is versioned, applied across a run rather than to
        // one day. A week that straddles a step down has two ceilings in it,
        // and drawing all seven against today's would restate the older half.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.byDay[wire(-7)] = [entry(2, mg: 3)]
        let versions = FakeVersions()
        versions.versions = [version(from: -30, startingCap: 18, currentCap: 18, quitAfter: 26)]
        let record = record(days, versions, clock: Clock(day(0)))

        await record.load()

        let newest = record.rollups.first?.capMg
        let oldest = record.rollups.last?.capMg
        #expect(newest != nil && oldest != nil)
        #expect(newest! < oldest!, "the whole week was drawn against one ceiling")
    }

    @Test("the day before last is not served under yesterday's heading")
    func aRecordThatOutlivesMidnightReReads() async {
        // This record is kept for the session, so an app left open overnight
        // asks it again for "yesterday" and means a different day. A boolean
        // guard would hand back the day before last with that day's cap beside
        // it, under a heading that says Yesterday.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.byDay[wire(0)] = [entry(2, mg: 9)]
        let clock = Clock(day(0))
        let record = record(days, FakeVersions(), clock: clock)

        await record.load()
        #expect(record.rollups.first?.loggedMg == 3)

        clock.now = day(1)
        await record.load()

        #expect(record.rollups.first?.loggedMg == 9, "midnight passed and yesterday did not move")
        // Two windows, each read once, and the second ends a day later than
        // the first — the whole run moves with midnight, not just its head.
        #expect(days.asked == ["\(wire(-7))…\(wire(-1))", "\(wire(-6))…\(wire(0))"])
    }

    @Test("returning to the log on the same day does not read again")
    func afinishedDayIsNotReReadForNothing() async {
        // The other half. A day that is over does not change while somebody
        // looks at it, so coming back to the log should cost nothing.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        let record = record(days, FakeVersions(), clock: Clock(day(0)))

        await record.load()
        await record.load()
        await record.load()

        #expect(days.asked.count == 1, "a finished day was read more than once")
    }

    @Test("a refresh that fails does not leave the old day under the heading")
    func aStaleDayIsNotKeptWhenTheNewOneFails() async {
        // The failure the date-keyed cache alone does not cover. A day that
        // loaded, then midnight, then a read that throws: the cache is cleared
        // but the rollup already in hand is for the day *before* yesterday, and
        // the section would draw it under the heading with that day's cap.
        //
        // The other failure test starts from nil, so it cannot see this.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        let clock = Clock(day(0))
        let record = record(days, FakeVersions(), clock: clock)

        await record.load()
        #expect(record.rollups.first?.loggedMg == 3)

        clock.now = day(1)
        days.fails = true
        await record.load()

        #expect(record.rollups.isEmpty, "the day before last was kept under yesterday's heading")
        #expect(record.isUnavailable)
    }

    @Test("a day that cannot be read says so rather than showing an empty one")
    func aFailedReadIsNotAQuietDay() async {
        let days = FakeDays(calendar: calendar)
        days.fails = true
        let record = record(days, FakeVersions(), clock: Clock(day(0)))

        await record.load()

        #expect(record.rollups.isEmpty, "a failed read drew a day with nothing on it")
        #expect(record.isUnavailable)
    }

    @Test("a day that failed to read can be read again")
    func aDroppedConnectionIsNotPermanent() async {
        // The cache exists to stop a *finished* day being re-read, not to make
        // a failed one final. Without clearing it, one dropped connection means
        // the section stays broken for the rest of the day however many times
        // somebody comes back to the log.
        //
        // The test above confirms the failure state and never asks whether it
        // can be left, which is exactly how this survived being written.
        let days = FakeDays(calendar: calendar)
        days.byDay[wire(-1)] = [entry(1, mg: 3)]
        days.fails = true
        let record = record(days, FakeVersions(), clock: Clock(day(0)))

        await record.load()
        #expect(record.isUnavailable)

        days.fails = false
        await record.load()

        #expect(record.rollups.first?.loggedMg == 3, "the day could not be read again after one failure")
        #expect(!record.isUnavailable, "the apology outlived the failure it was about")
    }
}
