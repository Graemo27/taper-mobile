import Foundation

/// The run so far, said back to the user in two sentences.
///
/// O6 is the only screen in onboarding that asks nothing. It exists because
/// the number it names is the one everything after it is measured against, and
/// a figure the user meets for the first time on the plan screen is a figure
/// they have no reason to believe.
///
/// Every part of it is either something they said or something the plan
/// actually does. Nothing here is encouragement with a number attached.
struct StartingLine: Equatable, Sendable {
    /// The daily figure, named plainly.
    var headline: String
    /// Their own answer read back, the reassurance, and what week one holds at.
    var body: String

    /// Builds the summary from a completed run, or returns nil while anything
    /// it rests on is still unanswered.
    ///
    /// `weekOneMg` comes from the plan rather than from the cap directly. They
    /// are the same number today, and the sentence promises they are — if the
    /// planner ever rounds or adjusts the first week, the copy has to move with
    /// it rather than keep describing the old behaviour.
    init?(plan: TaperPlan, dailyMg: Double, firstUse: FirstUseOption) {
        guard let weekOneMg = plan.weeklyCapsMg.first else { return nil }

        headline = "Your starting line: \(dailyMg.clean) mg a day."

        // No mention of triggers, though the board's copy has one. Triggers are
        // asked on the next screen, so anything said about them here would be
        // invented — and this screen's whole claim on the user's trust is that
        // it only repeats what they told us.
        body = """
        Your first one is \(firstUse.recap). That's not a verdict — it's a map. \
        Week one just holds steady at \(weekOneMg.clean) mg while you learn your pattern.
        """
    }
}
