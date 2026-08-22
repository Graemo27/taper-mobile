import Foundation
import Testing
@testable import Taper

/// A day's check-ins, and a count of how often they were asked for.
private final class FakeDays: CheckInReading, @unchecked Sendable {
    var byDay: [String: [StoredCheckIn]] = [:]
    var fails = false
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
        if fails { throw URLError(.notConnectedToInternet) }

        var days: [String] = []
        var cursor = calendar.startOfDay(for: min(first, last))
        let end = calendar.startOfDay(for: max(first, last))
        while cursor <= end {
            days.append(PlanDay.wireFormat(cursor, timeZone: calendar.timeZone))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return days.flatMap { byDay[$0] ?? [] }
    }
}

private final class FakeVersions: PlanVersionReading, @unchecked Sendable {
    var versions: [StoredPlanVersion] = []
    func versions() async throws -> [StoredPlanVersion] { versions }
}

/// Covers the day the log draws under today, including the one it must not
/// keep serving.
@MainActor
struct YesterdayRecordTests {
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
                      mg: mg, quantity: 1, createdAt: .testMoment)
    }

    private func record(_ days: FakeDays, _ plans: FakeVersions, clock: Clock) -> YesterdayRecord {
        YesterdayRecord(checkIns: days, plans: plans, calendar: calendar, today: { clock.now })
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

        #expect(record.rollup?.loggedMg == 6)
        #expect(record.rollup?.capMg == 12, "yesterday was not measured against its own plan")
        #expect(days.asked == [wire(-1)], "it read a day other than yesterday")
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
        #expect(record.rollup?.loggedMg == 3)

        clock.now = day(1)
        await record.load()

        #expect(record.rollup?.loggedMg == 9, "midnight passed and yesterday did not move")
        #expect(days.asked == [wire(-1), wire(0)])
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
        #expect(record.rollup?.loggedMg == 3)

        clock.now = day(1)
        days.fails = true
        await record.load()

        #expect(record.rollup == nil, "the day before last was kept under yesterday's heading")
        #expect(record.isUnavailable)
    }

    @Test("a day that cannot be read says so rather than showing an empty one")
    func aFailedReadIsNotAQuietDay() async {
        let days = FakeDays(calendar: calendar)
        days.fails = true
        let record = record(days, FakeVersions(), clock: Clock(day(0)))

        await record.load()

        #expect(record.rollup == nil, "a failed read drew a day with nothing on it")
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

        #expect(record.rollup?.loggedMg == 3, "the day could not be read again after one failure")
        #expect(!record.isUnavailable, "the apology outlived the failure it was about")
    }
}
