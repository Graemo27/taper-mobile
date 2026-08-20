import Foundation

/// Where a saved plan has got to, read back for the screen the app returns to.
///
/// Everything here comes from the five columns `taper_plans` keeps. That is the
/// schema's design — the schedule is recomputed rather than stored — and it has
/// one exception that this type exists to respect.
///
/// **Today's cap is the stored one, never a recomputed one.** `current_cap_mg`
/// is pinned deliberately: the number someone is currently living under must
/// not shift beneath them because a dependence answer was corrected or the plan
/// was stretched. Recomputing it from the descent would be right on most days
/// and quietly wrong on exactly the days that matter.
struct PlanProgress: Equatable, Sendable {
    /// The cap in force today, straight off the row.
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

        todaysCapMg = plan.currentCapMg

        // Clamped at one. A plan whose start is in the future is a clock the
        // app does not control — a device set back a day should read as day
        // one, not day zero or day minus one.
        let elapsed = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        day = max(1, elapsed + 1)

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

        nextStep = Self.nextStep(
            plan: plan,
            start: start,
            now: now,
            quitDate: quitDate,
            calendar: calendar
        )
    }

    /// The step after the current one, recomputed from the row.
    ///
    /// Recomputing is correct here and wrong for today's cap, which is the
    /// distinction the schema draws: what someone is living under now is
    /// pinned, and what comes next is derived.
    private static func nextStep(
        plan: StoredTaperPlan,
        start: Date,
        now: Date,
        quitDate: Date?,
        calendar: Calendar
    ) -> NextStep? {
        // A run holding where it is has no next step to name. Inventing one
        // would put a date in front of somebody who declined to set one.
        guard let quitDate else { return nil }

        let weeksToQuit = QuitDate.weeks(from: start, to: quitDate, calendar: calendar)
        let schedule = TaperPlanner.plan(for: TaperInput(
            startingCapMg: plan.startingCapMg,
            minutesToFirstUse: plan.firstUseMinutes,
            usesWhenIllInBed: plan.sickInBed,
            weeksUntilQuitDate: weeksToQuit
        )).weeklyCapsMg

        // Which week today falls in, and therefore which entry comes next.
        let elapsed = max(0, calendar.dateComponents([.day], from: start, to: now).day ?? 0)
        let nextIndex = elapsed / 7 + 1
        guard schedule.indices.contains(nextIndex) else { return nil }

        // The day that week begins, which is not tomorrow except on one day in
        // seven — the board's copy assumes the exception.
        guard let lands = calendar.date(byAdding: .day, value: nextIndex * 7, to: start) else {
            return nil
        }
        let inDays = calendar.dateComponents([.day], from: now, to: lands).day ?? 0
        guard inDays > 0 else { return nil }

        // A step has to be downward. The stored cap is pinned and the schedule
        // is recomputed, so the two can disagree — a plan stretched, a cap
        // corrected by hand, a row written by an older version — and the
        // arithmetic will happily produce a "next step" above the ceiling the
        // user is already living under. "Drops to 13.5" under a cap of 12 is
        // the shape of that, and it is worse than saying nothing.
        let next = schedule[nextIndex]
        guard next < plan.currentCapMg else { return nil }

        return NextStep(capMg: next, inDays: inDays)
    }
}
