import Foundation
import Testing
@testable import Taper

/// Covers reading a saved plan back into today's numbers.
///
/// The distinction the whole suite turns on is which figures are pinned and
/// which are recomputed. `current_cap_mg` is stored because the number someone
/// is living under must not move beneath them; everything after it is derived
/// from the same row.
struct PlanProgressTests {
    /// 9 October 2025, the day a plan started.
    private let start = "2025-10-09"

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let base = PlanDay.date(from: "2025-10-09")!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func plan(
        startingCap: Double = 18,
        currentCap: Double = 18,
        quitDate: String? = "2025-12-04",
        minutes: Int = 20,
        sickInBed: Bool = true
    ) -> StoredTaperPlan {
        StoredTaperPlan(
            id: 1,
            startingCapMg: startingCap,
            currentCapMg: currentCap,
            capEffectiveFrom: start,
            quitDate: quitDate,
            firstUseMinutes: minutes,
            sickInBed: sickInBed
        )
    }

    @Test("the first day of a plan is day one, not day zero")
    func theRunStartsAtOne() {
        #expect(PlanProgress(plan: plan(), today: day(0))?.day == 1)
        #expect(PlanProgress(plan: plan(), today: day(11))?.day == 12)
    }

    @Test("a clock set behind the plan's start still reads as day one")
    func aBackdatedClockDoesNotGoNegative() {
        // The start date is on the server and the clock is on the device, so
        // the two can disagree. Day zero or day minus one is a number no screen
        // should ever show.
        #expect(PlanProgress(plan: plan(), today: day(-3))?.day == 1)
    }

    @Test("today's cap is the stored one, never a recomputed one")
    func theCapInForceIsPinned() {
        // The schema pins `current_cap_mg` on purpose: a dependence answer
        // corrected, or a plan stretched, must not move the ceiling somebody is
        // already living under. A recomputed figure would be right on most days
        // and wrong on exactly the days that matter.
        let stretched = plan(startingCap: 18, currentCap: 11)
        #expect(PlanProgress(plan: stretched, today: day(20))?.todaysCapMg == 11)
    }

    @Test("the countdown runs from today, not from the day the plan started")
    func theCountdownMovesOnItsOwn() {
        // The one number on the home screen that changes without anyone doing
        // anything. 9 Oct to 4 Dec is 56 days.
        #expect(PlanProgress(plan: plan(), today: day(0))?.daysUntilQuitDate == 56)
        #expect(PlanProgress(plan: plan(), today: day(8))?.daysUntilQuitDate == 48)
        #expect(PlanProgress(plan: plan(), today: day(0))?.totalDays == 56)
    }

    @Test("the countdown stops at zero rather than going negative")
    func aPassedQuitDateReadsAsZero() {
        #expect(PlanProgress(plan: plan(), today: day(70))?.daysUntilQuitDate == 0)
    }

    @Test("the next step is named for the day it lands, not for tomorrow")
    func theStepIsNotAlwaysTomorrow() {
        // The board says "drops to 11.5 tomorrow", which is true on one day in
        // seven. On the other six that sentence is a promise the plan does not
        // keep.
        let onDayOne = PlanProgress(plan: plan(), today: day(0))?.nextStep
        #expect(onDayOne?.inDays == 7)
        #expect(onDayOne?.whenPhrase == "in 7 days")

        let dayBefore = PlanProgress(plan: plan(), today: day(6))?.nextStep
        #expect(dayBefore?.inDays == 1)
        #expect(dayBefore?.whenPhrase == "tomorrow")
    }

    @Test("the next cap is the planner's next step, recomputed from the row")
    func theNextCapComesFromTheSchedule() {
        // 18 mg over eight weeks steps to 16. Recomputing is correct *here* —
        // it is only today's cap that must not be derived.
        let schedule = TaperPlanner.plan(for: TaperInput(
            startingCapMg: 18, minutesToFirstUse: 20, usesWhenIllInBed: true, weeksUntilQuitDate: 8
        )).weeklyCapsMg
        #expect(schedule[1] == 16)
        #expect(PlanProgress(plan: plan(), today: day(0))?.nextStep?.capMg == 16)
    }

    @Test("a next step that is not a drop is not shown at all")
    func aStepMustGoDown() {
        // The stored cap is pinned and the schedule is recomputed, so the two
        // can disagree — a plan stretched, a cap corrected by hand, a row from
        // an older version. The arithmetic then produces a "next step" above
        // the ceiling somebody is already living under, and a tile reading
        // "12 mg — drops to 13.5" is worse than one that says nothing.
        let inconsistent = plan(startingCap: 18, currentCap: 12)
        let recomputed = TaperPlanner.plan(for: TaperInput(
            startingCapMg: 18, minutesToFirstUse: 20, usesWhenIllInBed: true, weeksUntilQuitDate: 8
        )).weeklyCapsMg
        #expect(recomputed[2] > 12, "the fixture must actually produce an upward step")

        #expect(PlanProgress(plan: inconsistent, today: day(11))?.nextStep == nil)
    }

    @Test("a run past the end of its schedule has no next step to name")
    func theEndHasNothingAfterIt() {
        #expect(PlanProgress(plan: plan(), today: day(70))?.nextStep == nil)
    }

    @Test("a run holding where it is gets no countdown and no next step")
    func aReductionOnlyRunPromisesNothing() {
        // Most nicotine users are not ready to name a date. Inventing a
        // countdown for them would put them back in the product they declined.
        let holding = plan(quitDate: nil)
        let progress = PlanProgress(plan: holding, today: day(3))
        #expect(progress?.daysUntilQuitDate == nil)
        #expect(progress?.totalDays == nil)
        #expect(progress?.nextStep == nil)
        #expect(progress?.day == 4)
        #expect(progress?.todaysCapMg == 18)
    }

    @Test("a quit date that cannot be read is refused, not read as no date")
    func anUnreadableQuitDateIsNotAnAbsence() {
        // The failure this prevents is silent and plausible: an unreadable
        // quit date treated as `nil` renders a perfectly ordinary
        // reduction-only plan — countdown gone, next step gone — and nothing
        // on screen suggests anything went wrong.
        let broken = StoredTaperPlan(
            id: 1, startingCapMg: 18, currentCapMg: 18,
            capEffectiveFrom: start, quitDate: "not a date",
            firstUseMinutes: 20, sickInBed: true
        )
        #expect(PlanProgress(plan: broken, today: day(0)) == nil)

        // And the same date spelled un-canonically, which the parser used to
        // take because `split` drops the empty piece.
        let looseSeparators = StoredTaperPlan(
            id: 1, startingCapMg: 18, currentCapMg: 18,
            capEffectiveFrom: start, quitDate: "2025--12-04",
            firstUseMinutes: 20, sickInBed: true
        )
        #expect(PlanProgress(plan: looseSeparators, today: day(0)) == nil)
    }

    @Test("a row whose date cannot be read yields no progress at all")
    func anUnreadableRowIsRefused() {
        let broken = StoredTaperPlan(
            id: 1, startingCapMg: 18, currentCapMg: 18,
            capEffectiveFrom: "not a date", quitDate: nil,
            firstUseMinutes: 20, sickInBed: true
        )
        #expect(PlanProgress(plan: broken, today: day(0)) == nil)
    }
}

/// Covers reading a stored day back, which has to be the exact mirror of
/// writing one.
struct PlanDayParsingTests {
    @Test("a day written is the same day read back")
    func writingAndReadingAgree() {
        // The pair is the seam: a parser disagreeing with the writer by one
        // time zone would put every plan a day out, in the direction nobody
        // notices until a countdown is wrong.
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let lateEvening = calendar.date(from: DateComponents(
            year: 2025, month: 10, day: 9, hour: 23, minute: 30
        ))!

        let written = PlanDay.wireFormat(lateEvening, timeZone: zone)
        #expect(written == "2025-10-09")
        let read = PlanDay.date(from: written, calendar: calendar)
        #expect(PlanDay.wireFormat(read!, timeZone: zone) == written)
    }

    @Test("a day is read as the start of that day, not as an instant mid-way")
    func parsingLandsOnMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parsed = PlanDay.date(from: "2025-10-09", calendar: calendar)!
        #expect(parsed == calendar.startOfDay(for: parsed))
    }

    @Test("an impossible date is refused rather than rolled forward")
    func februaryThirtyIsNotMarch() {
        // Building the date by hand would roll 30 February into March and
        // compute a plan from a day that does not exist.
        #expect(PlanDay.date(from: "2025-02-30") == nil)
        #expect(PlanDay.date(from: "2025-13-01") == nil)
        #expect(PlanDay.date(from: "2025-10") == nil)
        #expect(PlanDay.date(from: "") == nil)
    }

    @Test("a day the writer could never have produced is refused")
    func onlyCanonicalSpellingsAreAccepted() {
        // `split` drops empty pieces, so all of these come apart into three
        // usable numbers. A parser looser than its writer accepts strings the
        // app could not have written — and this value arrives from outside the
        // app, so the pair has to be exact by construction.
        #expect(PlanDay.date(from: "2025--10-09") == nil)
        #expect(PlanDay.date(from: "2025-10-09-") == nil)
        #expect(PlanDay.date(from: "-2025-10-09") == nil)
        #expect(PlanDay.date(from: "2025-10-9") == nil, "an unpadded day is not what the writer emits")
        #expect(PlanDay.date(from: "2025-1-09") == nil, "an unpadded month is not what the writer emits")
        // The canonical spelling still works.
        #expect(PlanDay.date(from: "2025-10-09") != nil)
    }

    @Test("a leap day is a real date")
    func februaryTwentyNineExistsInALeapYear() {
        #expect(PlanDay.date(from: "2024-02-29") != nil)
        #expect(PlanDay.date(from: "2025-02-29") == nil)
    }
}
