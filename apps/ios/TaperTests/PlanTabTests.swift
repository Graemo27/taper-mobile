import Foundation
import Testing
@testable import Taper

/// Covers what the plan tab says about a taper, including the three things the
/// board draws that this app has no source for.
@MainActor
struct PlanTabTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func progress(startingCap: Double = 18, currentCap: Double = 18,
                          quitInDays: Int? = 56, startedDaysAgo: Int = 0) -> PlanProgress {
        let today = Date(timeIntervalSince1970: 1_780_000_000)
        let started = calendar.date(byAdding: .day, value: -startedDaysAgo, to: today)!
        let quit = quitInDays.map { calendar.date(byAdding: .day, value: $0, to: today)! }
        return PlanProgress(
            plan: StoredTaperPlan(
                id: 1, startingCapMg: startingCap, currentCapMg: currentCap,
                capEffectiveFrom: PlanDay.wireFormat(started, timeZone: calendar.timeZone),
                quitDate: quit.map { PlanDay.wireFormat($0, timeZone: calendar.timeZone) },
                firstUseMinutes: 20, sickInBed: true
            ),
            today: today, calendar: calendar
        )!
    }

    private func view(_ p: PlanProgress) -> PlanTabView { PlanTabView(progress: p) }

    @Test("a plan with a date says where it ends, one without says it holds")
    func theSummaryMatchesTheKindOfPlan() {
        // A run holding where it is has not failed at reaching zero — it is a
        // supported state, and "down to zero" would be the screen telling
        // somebody about a plan they did not agree to.
        #expect(view(progress()).summary.contains("down to zero"))
        #expect(view(progress(quitInDays: nil)).summary.contains("holding steady"))
        #expect(view(progress(quitInDays: nil)).summary.contains("down to zero") == false)
    }

    @Test("a plateau is one row, and the week after it keeps its real number")
    func aFlatStretchIsOneRowAndDoesNotShiftTheRest() {
        // A slow descent repeats: rounding to the half-milligram gives
        // 9, 8.5, 8.5, 8… so three identical rows would read as a fault. But
        // collapsing them shortens the list, and a label taken from list
        // position then names the following week one week early.
        let plan = progress(startingCap: 9, quitInDays: 182)
        let view = view(plan)
        let steps = view.steps

        #expect(steps.map(\.capMg).count == Set(steps.map(\.capMg)).count, "a figure repeated")

        // Every week in the schedule is covered exactly once, in order.
        let covered = steps.flatMap { Array($0.weeks) }
        #expect(covered == Array(plan.weeklyCapsMg.indices), "the rows do not tile the schedule")

        // And a row that follows a plateau says which weeks it really is.
        if let plateau = steps.first(where: { $0.weeks.count > 1 }) {
            #expect(view.weekLabel(plateau).hasPrefix("Weeks "), "a plateau named a single week")
        } else {
            Issue.record("this schedule was expected to contain a plateau")
        }
    }

    @Test("a descent to a date ends at zero and starts where the plan starts")
    func theListIsTheRealSchedule() {
        let plan = progress()
        let steps = view(plan).steps

        #expect(steps.first?.capMg == plan.weeklyCapsMg.first, "the list did not start at the cap")
        #expect(steps.last?.capMg == 0, "a plan with a quit date did not reach zero")
        #expect(steps.map(\.capMg) == steps.map(\.capMg).sorted(by: >), "the descent did not descend")
    }

    @Test("dependence is named, and nothing is claimed about other people")
    func noPopulationFigureIsInvented() {
        // The board reads "You are like 11% of Quitters". There is no source
        // for that figure in this project, and `TaperPlan` states outright that
        // it exposes no success rate or confidence figure — so the band names
        // the dependence and stops.
        let text = view(progress()).dependenceText

        #expect(["Lower dependence", "Moderate dependence", "Higher dependence"].contains(text))
        #expect(!text.contains("%"), "a population statistic reached the screen")
    }

    @Test("this week is called this week, and later weeks keep their number")
    func theFirstRowIsNotWeekOne() {
        // "Week 1" for the week somebody is in the middle of is a small lie
        // that costs a moment of arithmetic every time it is read.
        let view = view(progress())

        #expect(view.weekLabel(.init(weeks: 0...0, capMg: 18)) == "This week")
        #expect(view.weekLabel(.init(weeks: 3...3, capMg: 9)) == "Week 4")
        #expect(view.weekLabel(.init(weeks: 4...5, capMg: 7)) == "Weeks 5–6")
    }

    @Test("a plan that started weeks ago does not call its first row this week")
    func theCurrentRowFollowsTheClockNotTheList() {
        // The schedule starts at the plan's first week, not at this one. On a
        // plan three weeks old the top row is a ceiling that expired a
        // fortnight ago — and marking it current is how somebody ends up
        // following it. It would also disagree with the cap on the home screen,
        // which counts from the same day this now does.
        let view = view(progress(startedDaysAgo: 15))

        #expect(view.currentWeek == 2, "the week in force was not read from the plan's age")
        #expect(view.weekLabel(.init(weeks: 0...0, capMg: 18)) == "Week 1", "a past cap was current")
        #expect(view.weekLabel(.init(weeks: 2...2, capMg: 13.5)) == "This week")
        #expect(!view.isCurrent(.init(weeks: 0...0, capMg: 18)))
        #expect(view.isCurrent(.init(weeks: 2...2, capMg: 13.5)))

        // And a plateau spanning the current week is the current row too.
        #expect(view.isCurrent(.init(weeks: 1...3, capMg: 14)))
    }

    @Test("the seventh day of the plan is still its first week")
    func theWeekTurnsOnTheEighthDay() {
        // The boundary is the only place the arithmetic can be wrong without
        // looking wrong: mid-week, an off-by-one in the divisor lands on the
        // same answer. Day seven is the last day of week one; day eight starts
        // week two, and the ceiling steps down with it.
        #expect(view(progress(startedDaysAgo: 0)).currentWeek == 0, "day one was not week one")
        #expect(view(progress(startedDaysAgo: 6)).currentWeek == 0, "day seven left week one early")
        #expect(view(progress(startedDaysAgo: 7)).currentWeek == 1, "day eight did not start week two")
        #expect(view(progress(startedDaysAgo: 13)).currentWeek == 1)
        #expect(view(progress(startedDaysAgo: 14)).currentWeek == 2)
    }

    @Test("the plan tab agrees with the cap the rest of the app is using")
    func theHighlightedRowIsTodaysCeiling() {
        // The one thing this screen cannot get wrong. Two models of one plan is
        // what once put "18 mg — drops to 13.5" on screen in a week when the
        // real next step was 16.
        let plan = progress(startedDaysAgo: 15)
        let view = view(plan)
        let current = view.steps.first { view.isCurrent($0) }

        #expect(current?.capMg == plan.todaysCapMg, "the marked row is not today's cap")
    }

    @Test("the note reassures without claiming a duration nobody sourced")
    func theNoteMakesNoPromise() {
        let note = PlanTabView.reassurance

        // The reassurance survives — being slow is not failing.
        #expect(note.contains("right pace"))
        #expect(!note.lowercased().contains("succeed"))
        #expect(!note.contains("%"))

        // But not the duration claim. The research wiki has notes on NRT's
        // efficacy, dose bands and cardiac safety, and none on how long it is
        // safe to stay on it — so the app does not answer that, it routes it.
        #expect(!note.lowercased().contains("as long as you need"))
        #expect(note.lowercased().contains("as directed"))
        #expect(note.lowercased().contains("pharmacist"))
    }
}
