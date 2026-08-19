import Foundation

/// One stop on the plan's timeline.
///
/// A title and a line under it, both fully written here rather than assembled
/// in the view. Every one of them quotes a figure the planner chose, and a
/// screen that builds its own sentences around those figures is a second place
/// the numbers can drift.
struct PlanMilestone: Equatable, Sendable, Identifiable {
    var title: String
    var detail: String

    var id: String { title }
}

/// O11 — the whole plan, said back before the user agrees to it.
///
/// The board draws one run: a quit date, a descent, a countdown. Three shapes it
/// does not draw are the ones this type exists for.
///
/// A run with no date has no descent and no countdown, and must not be shown a
/// borrowed one — the planner holds a single cap for that user deliberately, and
/// the screen has to hold with it. A stretched run has a schedule longer than
/// the date the user picked, so the countdown comes off the plan rather than off
/// their date; quoting their date over a schedule that outlasts it is the app
/// disagreeing with itself on the last screen before it asks for commitment. And
/// an intake high enough to look like a mis-entry has a flag on `TaperPlan` that
/// nothing has ever rendered — this is the last screen before someone starts
/// counting against it.
struct PlanPreview: Equatable, Sendable {
    /// The ceiling for this week — the only figure the user acts on today.
    var capMg: Double
    /// Days to the end of the descent, or nil for a run holding where it is.
    ///
    /// Counted off the plan's own length, never off the requested date. When
    /// the two differ the plan is the one that will actually happen.
    var countdownDays: Int?
    /// The day the descent reaches zero, or nil when there is no descent.
    ///
    /// Carried as a date as well as inside the milestone's wording, so the
    /// arithmetic can be asserted without going through a locale's month names.
    var quitDate: Date?
    var milestones: [PlanMilestone]
    /// The reassurance under the timeline.
    var note: String
    /// Present only when the stated intake reads as a data-entry error.
    var caution: String?

    /// Builds the preview, or returns nil when there is no plan to describe.
    ///
    /// `today` is passed in rather than read. The countdown and the date on the
    /// last milestone have to come from one reading of the clock: taking two
    /// lets a run that crosses midnight between them land the final step a day
    /// off the countdown printed above it.
    init?(
        plan: TaperPlan,
        today: Date,
        treatments: Set<TreatmentForm>,
        calendar: Calendar = .current
    ) {
        guard let cap = plan.weeklyCapsMg.first else { return nil }
        capMg = cap
        caution = Self.caution(cap: cap, isImplausible: plan.intakeLooksImplausible)

        let hold = PlanMilestone(
            title: "Hold at \(cap.clean) mg — this week",
            detail: "Nothing moves yet. Log what you use and let the week show you your pattern."
        )

        // `reachesZero` rather than a week count. A run with no date holds one
        // cap forever, and anything that ends above zero is not a thing to put
        // a countdown on.
        guard plan.reachesZero, plan.weeklyCapsMg.count > 1 else {
            countdownDays = nil
            quitDate = nil
            milestones = [hold, Self.openDoor]
            // Conditional rather than encouraging. The one trial that set out to
            // reach people who were not ready scored best on "if and when",
            // and a reduction-only run is exactly that user
            // (`readiness-to-quit-spectrum`).
            note = """
            No date, no countdown. Reducing counts on its own — and if and when you want a date, \
            the plan sizes the steps for you.
            """
            return
        }

        let weeks = plan.weeklyCapsMg.count - 1
        countdownDays = weeks * 7
        let landing = QuitDate.date(weeksFrom: today, weeks: weeks, calendar: calendar)
        quitDate = landing

        milestones = [
            hold,
            Self.descent(from: cap, to: plan.weeklyCapsMg[1], weeks: weeks),
            PlanMilestone(
                title: "\(landing.formatted(.dateTime.month(.wide).day())) — your quit date",
                detail: Self.landingDetail(
                    treatments: treatments,
                    fastActingMg: plan.replacement.fastActingMg
                )
            ),
        ]

        note = """
        Slip a week? The plan stretches with you — the cap holds where it is until you're ready \
        to drop again.
        """
    }

    /// The second stop for a run that is not going anywhere yet.
    ///
    /// It promises no rate. The planner produces no descent without a date, so
    /// naming a weekly step here would be the screen inventing the one number
    /// the model refused to supply.
    private static let openDoor = PlanMilestone(
        title: "Step down when it feels right",
        detail: "The cap holds here until you say otherwise. Drop it whenever the last week felt easy."
    )

    /// The descent, described by what happens next week rather than by an
    /// average.
    ///
    /// The first step is the one the user has to actually make, and rounding to
    /// the half-milligram leaves later steps uneven — so an average would be a
    /// figure that matches no week in the plan.
    private static func descent(from cap: Double, to next: Double, weeks: Int) -> PlanMilestone {
        let step = cap - next
        return PlanMilestone(
            // A light intake spread over a long floor can round to no drop at
            // all in week two. "About 0 mg a week" is worse than saying less.
            title: step < 0.5 ? "Step down a little at a time" : "Step down about \(step.clean) mg a week",
            detail: """
            \(weeks) steps, sized to how deep the habit runs. A schedule you can keep beats a \
            faster one you can't.
            """
        )
    }

    /// What comes off last, given what the user chose to taper with.
    ///
    /// Three branches because all three happen: someone on a fast-acting form,
    /// someone on the patch alone, and someone who declined a treatment
    /// outright. The last is a real answer rather than an unfinished one, and
    /// telling that user about a lozenge they said no to is the screen not
    /// having listened.
    private static func landingDetail(treatments: Set<TreatmentForm>, fastActingMg: Int) -> String {
        if let form = TreatmentForm.allCases.first(where: { treatments.contains($0) && !$0.isPatch }) {
            return "Land at 0, with \(fastActingMg) mg \(form.label.lowercased()) for the cravings that outlast the taper."
        }
        if treatments.contains(.patch) {
            return "Land at 0. The patch is the last thing to come off."
        }
        return "Land at 0. Nothing to come off afterwards — the cap simply runs out."
    }

    /// The warning for an intake that reads as a mis-entry.
    ///
    /// `TaperPlan` has carried this flag since the planner was written and no
    /// screen has ever shown it. A cap set from a mistyped strength is not a
    /// cap that fails loudly — it is one that never binds, so the app agrees
    /// with everything the user logs and the taper quietly does nothing.
    private static func caution(cap: Double, isImplausible: Bool) -> String? {
        guard isImplausible else { return nil }
        return """
        \(cap.clean) mg a day is more than heavy cigarette use delivers. Worth checking the \
        strength and the count you gave — a cap this high won't ask anything of you.
        """
    }
}
