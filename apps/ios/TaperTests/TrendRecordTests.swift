import Foundation
import Testing
@testable import Taper

/// A span of days on demand, with a knob for failing and one for stalling.
private final class FakeTrendDays: CheckInReading, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()
    private let calendar: Calendar

    private struct State {
        var byDay: [String: [StoredCheckIn]] = [:]
        var fails = false
        var holds = false
        var asked: [String] = []
    }

    init(calendar: Calendar) { self.calendar = calendar }

    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    var holds: Bool {
        get { lock.withLock { state.holds } }
        set { lock.withLock { state.holds = newValue } }
    }
    var asked: [String] { lock.withLock { state.asked } }

    func set(_ wire: String, _ entries: [StoredCheckIn]) {
        lock.withLock { state.byDay[wire] = entries }
    }

    func entries(from first: Date, to last: Date) async throws -> [StoredCheckIn] {
        let from = PlanDay.wireFormat(first, timeZone: calendar.timeZone)
        let to = PlanDay.wireFormat(last, timeZone: calendar.timeZone)
        lock.withLock { state.asked.append("\(from)…\(to)") }
        while holds { await Task.yield() }
        let (fails, byDay) = lock.withLock { (state.fails, state.byDay) }
        if fails { throw URLError(.notConnectedToInternet) }

        var days: [String] = []
        var cursor = calendar.startOfDay(for: first)
        while cursor <= last {
            days.append(PlanDay.wireFormat(cursor, timeZone: calendar.timeZone))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return days.flatMap { key in
            (byDay[key] ?? []).map {
                StoredCheckIn(id: $0.id, ledger: $0.ledger, label: $0.label, form: $0.form,
                              mg: $0.mg, quantity: $0.quantity, loggedOn: key,
                              createdAt: $0.createdAt)
            }
        }
    }
}

private final class FakeTrendVersions: PlanVersionReading, @unchecked Sendable {
    var stored: [StoredPlanVersion] = []
    func versions() async throws -> [StoredPlanVersion] { stored }
}

/// Covers the graph's record: what it reads, what it caches on, and what a
/// stale read is refused.
@MainActor
struct TrendRecordTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var anchor: Date { Date(timeIntervalSince1970: 1_780_000_000) }

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: anchor))!
    }
    private func wire(_ offset: Int) -> String {
        PlanDay.wireFormat(day(offset), timeZone: calendar.timeZone)
    }
    private func entry(_ id: Int, mg: Double) -> StoredCheckIn {
        StoredCheckIn(id: id, ledger: .source, label: "Pouch", form: .pouch,
                      mg: mg, quantity: 1, loggedOn: wire(0), createdAt: anchor)
    }
    private func plan(from offset: Int) -> StoredPlanVersion {
        StoredPlanVersion(effectiveFrom: wire(offset), startingCapMg: 18,
                          currentCapMg: 12, quitDate: nil,
                          firstUseMinutes: 20, sickInBed: true)
    }

    private func record(
        _ days: FakeTrendDays, _ plans: FakeTrendVersions, clock: Clock
    ) -> TrendRecord {
        TrendRecord(checkIns: days, plans: plans, calendar: calendar, today: { clock.now })
    }

    @Test("a week reads six finished days, and today arrives by hand")
    func todayIsAnInputNotAFetch() async {
        // The finding this shape answers: with today inside the cached
        // window, a check-in made after the read never reached the graph
        // until midnight or a toggle.
        let days = FakeTrendDays(calendar: calendar)
        let plans = FakeTrendVersions()
        plans.stored = [plan(from: -40)]
        let record = record(days, plans, clock: Clock(anchor))

        await record.load()

        #expect(days.asked == ["\(wire(-6))…\(wire(-1))"], "the read included today")

        let before = record.trend(today: [])
        #expect(before?.bars.count == 7)
        #expect(before?.bars.last?.isToday == true)
        #expect(before?.bars.last?.fraction == 0)

        // The same tap home's card sees, visible with no second read.
        let after = record.trend(today: [entry(1, mg: 3)])
        #expect(after?.bars.last?.fraction ?? 0 > 0,
                "a check-in made after the read never reached the graph")
        #expect(days.asked.count == 1)
    }

    @Test("a finished read is not repeated, and a new day or span is")
    func theCacheKnowsWhatItIsHolding() async {
        let days = FakeTrendDays(calendar: calendar)
        let plans = FakeTrendVersions()
        plans.stored = [plan(from: -40)]
        let clock = Clock(anchor)
        let record = record(days, plans, clock: clock)

        await record.load()
        await record.load()
        #expect(days.asked.count == 1, "the same day and span was read twice")

        await record.show(.month)
        #expect(days.asked.count == 2)
        #expect(days.asked.last == "\(wire(-29))…\(wire(-1))")
        #expect(record.trend(today: [])?.bars.count == 30)

        clock.now = day(1)
        await record.load()
        #expect(days.asked.count == 3, "midnight did not invalidate the cache")
    }

    @Test("a run the day outran refuses to draw, and is not published")
    func midnightRefusesTheStaleRun() async {
        // The same door every stale-publish defect in PastDaysRecord came
        // through: something written after an await by an operation that is
        // no longer the current one.
        let days = FakeTrendDays(calendar: calendar)
        let plans = FakeTrendVersions()
        plans.stored = [plan(from: -40)]
        let clock = Clock(anchor)
        let record = record(days, plans, clock: clock)

        days.holds = true
        let stale = Task { await record.load() }
        let deadline = Date().addingTimeInterval(2)
        while days.asked.isEmpty, Date() < deadline { await Task.yield() }

        clock.now = day(1)
        days.holds = false
        _ = await stale.value

        #expect(record.trend(today: []) == nil,
                "a run ending two days back was drawn as ending yesterday")

        await record.load()
        #expect(record.trend(today: [])?.bars.last?.day == calendar.startOfDay(for: day(1)),
                "the re-read did not answer for the new day")
    }

    @Test("a failed midnight re-read drops yesterday's run rather than mislabel it")
    func yesterdayIsNotDrawnAsToday() async {
        // The window loads, the day turns, and the re-read fails. Keeping the
        // old bars would mark yesterday's final bar as today — a graph lying
        // about which day it is — so the stale run is dropped and the card
        // apologises instead.
        let days = FakeTrendDays(calendar: calendar)
        let plans = FakeTrendVersions()
        plans.stored = [plan(from: -40)]
        let clock = Clock(anchor)
        let record = record(days, plans, clock: clock)
        await record.load()
        #expect(record.trend(today: []) != nil)

        clock.now = day(1)
        days.fails = true
        await record.load()

        #expect(record.trend(today: []) == nil, "yesterday's run survived a failed re-read")
        #expect(record.isUnavailable, "the stale run was dropped silently")

        days.fails = false
        await record.load()
        #expect(record.trend(today: []) != nil)
        #expect(record.isUnavailable == false)
    }

    @Test("a failed first read says so, and a retry takes it back")
    func theApologyIsNotPermanent() async {
        let days = FakeTrendDays(calendar: calendar)
        let plans = FakeTrendVersions()
        plans.stored = [plan(from: -40)]
        let record = record(days, plans, clock: Clock(anchor))

        days.fails = true
        await record.load()
        #expect(record.isUnavailable, "a failed read left the card silent")

        days.fails = false
        await record.load()
        #expect(record.isUnavailable == false)
        #expect(record.trend(today: []) != nil, "the retry was refused by the cache")
    }

    @Test("a month is not a week with a different name")
    func theTogglesDoNotShareBars() async {
        // Bars held for one span refuse to draw under the other's toggle.
        let days = FakeTrendDays(calendar: calendar)
        let plans = FakeTrendVersions()
        plans.stored = [plan(from: -40)]
        let record = record(days, plans, clock: Clock(anchor))
        await record.load()

        days.holds = true
        let switching = Task { await record.show(.month) }
        let deadline = Date().addingTimeInterval(2)
        while days.asked.count < 2, Date() < deadline { await Task.yield() }
        #expect(record.trend(today: []) == nil,
                "a week of bars stayed drawn under the Month toggle")
        days.holds = false
        _ = await switching.value

        #expect(record.trend(today: [])?.bars.count == 30)
    }
}
