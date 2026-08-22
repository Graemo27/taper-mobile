import Foundation
import Testing
@testable import Taper

/// Covers what a day that has already happened was measured against.
@MainActor
struct PlanHistoryTests {
    private let calendar = Calendar(identifier: .gregorian)

    /// A fixed day to count from, so nothing here depends on when it runs.
    private var anchor: Date { Date(timeIntervalSince1970: 1_780_000_000) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: anchor))!
    }

    private func version(
        from offset: Int, startingCap: Double = 18, currentCap: Double = 18,
        quitAfter: Int? = nil, firstUse: Int = 20, sick: Bool = true
    ) -> StoredPlanVersion {
        StoredPlanVersion(
            effectiveFrom: PlanDay.wireFormat(day(offset), timeZone: calendar.timeZone),
            startingCapMg: startingCap,
            currentCapMg: currentCap,
            quitDate: quitAfter.map { PlanDay.wireFormat(day($0), timeZone: calendar.timeZone) },
            firstUseMinutes: firstUse,
            sickInBed: sick
        )
    }

    private func history(_ versions: [StoredPlanVersion]) -> PlanHistory {
        PlanHistory(versions: versions, calendar: calendar)
    }

    @Test("a day before the plan began has no ceiling, not a ceiling of zero")
    func aDayBeforeTheStartIsUnknown() {
        // Zero would render every check-in on that day as infinitely over — a
        // bar the colour of failure across somebody's first week, for days they
        // were not being measured on at all.
        let history = history([version(from: 0)])

        #expect(history.cap(on: day(-1)) == nil)
        #expect(history.cap(on: day(0)) != nil, "the day the plan began is covered by it")
    }

    @Test("a quit date that will not parse takes the day with it")
    func aCorruptVersionDoesNotAnswerConfidently() {
        // The failure this avoids is a silent one. Reading an unreadable date
        // as "no quit date" picks a different, flatter schedule and hands back
        // a ceiling that looks perfectly ordinary — a wrong number with nothing
        // about it to notice.
        let corrupt = StoredPlanVersion(
            effectiveFrom: PlanDay.wireFormat(day(0), timeZone: calendar.timeZone),
            startingCapMg: 18, currentCapMg: 18,
            quitDate: "not a date", firstUseMinutes: 20, sickInBed: true
        )

        #expect(history([corrupt]).cap(on: day(3)) == nil, "a corrupt version answered anyway")

        // And a version with no quit date at all is fine — absent is a fact,
        // unreadable is not.
        #expect(history([version(from: 0, quitAfter: nil)]).cap(on: day(3)) != nil)
    }

    @Test("a day reads the version that was in force on it, not the newest one")
    func anOlderDayKeepsItsOwnPlan() {
        // The whole reason the table exists. Somebody who re-planned down to
        // 9 mg on day 30 was living under 18 mg on day 10, and the log has to
        // say so — otherwise last month is restated under this month's answers.
        let history = history([
            version(from: 0, currentCap: 18),
            version(from: 30, startingCap: 18, currentCap: 9),
        ])

        #expect(history.cap(on: day(10)) == 18)
        #expect(history.cap(on: day(31)) == 9)
    }

    @Test("the ceiling steps down inside a version, with no row changing")
    func theDescentIsRecomputedRatherThanStored() {
        // The reason a table of cap periods could not have answered this: the
        // cap falls every week while the version sits still, because the
        // schedule is derived. Days six and seven are one apart and a week
        // apart.
        let history = history([version(from: 0, startingCap: 18, currentCap: 18, quitAfter: 56)])

        let firstWeek = history.cap(on: day(6))
        let secondWeek = history.cap(on: day(7))

        #expect(firstWeek == 18)
        #expect(secondWeek != nil)
        #expect(secondWeek! < firstWeek!, "the ceiling did not step down after seven days")
    }

    @Test("past the end of the descent the ceiling is the last step, not the pin")
    func aFinishedTaperIsNotItsStartingFigure() {
        // Day two hundred of a fifty-six day plan. Falling back to the pinned
        // figure would report the cap somebody started at as the one they were
        // living under after they had finished.
        let history = history([version(from: 0, startingCap: 18, currentCap: 18, quitAfter: 56)])

        #expect(history.cap(on: day(200)) == 0)
    }

    @Test("a pin lowers the ceiling and never raises it")
    func aCorrectedCapIsHonouredDownwards() {
        // A cap corrected by hand, or a plan stretched, must not hand somebody
        // back headroom they had already given up.
        let generous = history([version(from: 0, startingCap: 18, currentCap: 18, quitAfter: 56)])
        let pinned = history([version(from: 0, startingCap: 18, currentCap: 6, quitAfter: 56)])

        #expect(generous.cap(on: day(0)) == 18)
        #expect(pinned.cap(on: day(0)) == 6, "the pin did not lower the first week")
    }

    @Test("versions handed over in any order still answer for the right day")
    func theReadDoesNotDependOnTheStoresOrdering() {
        // The store returns newest first. Nothing should break if that changes,
        // because an ordering nobody declared is one that drifts.
        let ascending = history([version(from: 0, currentCap: 18), version(from: 30, currentCap: 9)])
        let descending = history([version(from: 30, currentCap: 9), version(from: 0, currentCap: 18)])

        #expect(ascending.cap(on: day(10)) == descending.cap(on: day(10)))
        #expect(ascending.cap(on: day(31)) == descending.cap(on: day(31)))
    }
}
