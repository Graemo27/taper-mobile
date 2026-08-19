import Foundation

/// The calendar arithmetic `TaperPlanner` deliberately refuses to do.
///
/// The planner counts in weeks and has no clock, no time zone and nothing to
/// stub — that is what makes it a pure function. Turning a date into a number
/// of weeks is the caller's job, and this is the caller.
enum QuitDate {
    /// Whole weeks between two days, floored, and never less than one.
    ///
    /// Floored rather than rounded because the direction matters: giving the
    /// plan more weeks than the user actually has would land the final step
    /// after the date they picked. Ten days is one week of runway, not one and
    /// a half.
    ///
    /// Compares calendar days rather than elapsed time, so a date chosen at
    /// 11pm is not a day short of one chosen at 9am.
    static func weeks(from today: Date, to date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days / 7)
    }

    /// The date a given number of weeks out, for defaults and previews.
    static func date(weeksFrom today: Date, weeks: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: today)) ?? today
    }
}

/// What O10 says about the date the user has landed on.
///
/// The screen's job is not to collect a date but to tell the user what that
/// date means for their plan — and the case worth building carefully is the one
/// the board does not draw: a date sooner than the descent can safely reach.
struct QuitDateSummary: Equatable, Sendable {
    /// The pill beside the date.
    var runway: String
    /// The sentence under it.
    var caption: String
    /// True when the plan will take longer than the date the user chose.
    ///
    /// The planner stretches rather than compressing, because a schedule too
    /// steep to keep is worse than no schedule — failing one was associated
    /// with worse outcomes than never being given one. That stretch has to be
    /// visible here, or the app quietly disagrees with the date on screen.
    var isStretched: Bool

    init(plan: TaperPlan, requestedWeeks: Int, startingCapMg: Double) {
        runway = requestedWeeks == 1 ? "1 week out" : "\(requestedWeeks) weeks out"

        if let requested = plan.stretchedFromRequestedWeeks {
            isStretched = true
            let actual = plan.weeklyCapsMg.count - 1
            caption = """
            \(requested == 1 ? "A week" : "\(requested) weeks") is quicker than your steps can \
            safely go. The plan will take \(actual) weeks instead, and the countdown starts only \
            when you confirm.
            """
        } else {
            isStretched = false
            caption = """
            That's enough runway to step \(startingCapMg.clean) → 0 without any cliff. \
            The countdown starts only when you confirm.
            """
        }
    }
}
