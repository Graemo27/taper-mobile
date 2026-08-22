import Foundation

/// Where a saved plan has got to, read back for the screen the app returns to.
///
/// Everything here comes from the five columns `taper_plans` keeps, and every
/// figure comes off **one** recomputed descent. Reading today's cap from the
/// row and the next step from a schedule was two models of the same plan, and
/// the two drift the moment a week passes: nothing in the app advances
/// `current_cap_mg`, so the row keeps saying what onboarding wrote while the
/// derived step walks on down without it.
struct PlanProgress: Equatable, Sendable {
    /// The cap in force today.
    var todaysCapMg: Double
    /// Which day of the plan today is, counting the first day as day one.
    var day: Int
    /// The plan's length in days, or nil for a run with no quit date.
    var totalDays: Int?
    /// Days from today to the quit date, or nil when there is none.
    var daysUntilQuitDate: Int?
    /// The next step down, and when it lands. Nil once there are no more.
    var nextStep: NextStep?

    /// The cap after this one, and how far off it is.
    struct NextStep: Equatable, Sendable {
        var capMg: Double
        /// Days from today until it applies. Never zero — a step landing today
        /// is already today's cap.
        var inDays: Int

        /// "tomorrow" or "in 5 days", because the board's wording is only true
        /// on the last day of a week and this has to be right on the other six.
        var whenPhrase: String {
            inDays == 1 ? "tomorrow" : "in \(inDays) days"
        }
    }

    /// Rebuilds today's picture, or returns nil when the row cannot be read as
    /// a plan.
    ///
    /// `today` is passed in rather than read, because every number here is a
    /// difference from it and a type that consults the clock cannot be tested
    /// on the day a step lands.
    init?(plan: StoredTaperPlan, today: Date, calendar: Calendar = .current) {
        guard let start = PlanDay.date(from: plan.capEffectiveFrom, calendar: calendar) else {
            return nil
        }
        // A quit date that will not parse is refused, not treated as absent.
        // `flatMap` would turn an unreadable value into `nil`, which this type
        // reads as "this person chose to hold where they are" — so a corrupt
        // row would silently render as a reduction-only plan, countdown gone
        // and nobody told. The read protocol makes the same distinction one
        // file over: nil means they have none, never that we could not tell.
        let quitDate: Date?
        switch plan.quitDate {
        case let .some(wire):
            guard let parsed = PlanDay.date(from: wire, calendar: calendar) else { return nil }
            quitDate = parsed
        case .none:
            quitDate = nil
        }
        let now = calendar.startOfDay(for: today)

        // Clamped at zero. A plan whose start is in the future is a clock the
        // app does not control — a device set back a day should read as day
        // one, not day zero or day minus one.
        let elapsed = max(0, calendar.dateComponents([.day], from: start, to: now).day ?? 0)
        day = elapsed + 1
        let week = elapsed / 7

        if let quitDate {
            let span = calendar.dateComponents([.day], from: start, to: quitDate).day ?? 0
            totalDays = max(1, span)
            // From today, not from the start. The countdown is the one number
            // on the home screen that changes without anybody doing anything.
            daysUntilQuitDate = max(0, calendar.dateComponents([.day], from: now, to: quitDate).day ?? 0)
        } else {
            totalDays = nil
            daysUntilQuitDate = nil
        }

        // Built once, and both figures on the tile come off it. Two models of
        // one plan is what put "18 mg — drops to 13.5" on the screen in week
        // two: the row standing where onboarding left it while the derived
        // step walked straight past the 16 mg week between them.
        let schedule = TaperPlanner.plan(for: TaperInput(
            startingCapMg: plan.startingCapMg,
            minutesToFirstUse: plan.firstUseMinutes,
            usesWhenIllInBed: plan.sickInBed,
            weeksUntilQuitDate: quitDate.map {
                QuitDate.weeks(from: start, to: $0, calendar: calendar)
            }
        )).weeklyCapsMg

        // The same rule every past day is read by, so home and the log cannot
        // disagree about one day.
        todaysCapMg = TaperCap.inForce(
            pinned: plan.currentCapMg, schedule: schedule, week: week
        )
        nextStep = Self.nextStep(
            schedule: schedule,
            week: week,
            capInForce: todaysCapMg,
            start: start,
            now: now,
            calendar: calendar
        )
    }

    /// The step after this week, and when it lands.
    ///
    /// Off the same array as the cap above it, so the two are consecutive by
    /// construction rather than by agreement.
    private static func nextStep(
        schedule: [Double],
        week: Int,
        capInForce: Double,
        start: Date,
        now: Date,
        calendar: Calendar
    ) -> NextStep? {
        // A run holding where it is has a one-entry schedule, so it falls out
        // here rather than needing a case of its own — and falling out is the
        // right answer: inventing a step would put a date in front of somebody
        // who declined to set one.
        let nextIndex = week + 1
        guard schedule.indices.contains(nextIndex) else { return nil }

        // The day that week begins, which is not tomorrow except on one day in
        // seven — the board's copy assumes the exception.
        guard let lands = calendar.date(byAdding: .day, value: nextIndex * 7, to: start) else {
            return nil
        }
        let inDays = calendar.dateComponents([.day], from: now, to: lands).day ?? 0
        guard inDays > 0 else { return nil }

        // A step has to be downward. A row pinned below the descent — a plan
        // stretched, a cap corrected by hand, a row written by an older
        // version — leaves the next scheduled entry above the ceiling somebody
        // is already living under, and a tile reading "12 mg — drops to 13.5"
        // is worse than one that says nothing.
        let next = schedule[nextIndex]
        guard next < capInForce else { return nil }

        return NextStep(capMg: next, inDays: inDays)
    }
}
