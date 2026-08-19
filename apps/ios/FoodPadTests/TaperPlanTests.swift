import Testing
@testable import FoodPad

/// The plan generator is where the research constraints bite, so these tests are
/// mostly assertions that it refuses to do the harmful thing rather than that it
/// produces a particular curve.
struct TaperPlanTests {
    /// Six 3 mg pouches a day — the onboarding example — with a light habit.
    private func input(
        capMg: Double = 18,
        minutesToFirstUse: Int = 90,
        usesWhenIllInBed: Bool = false,
        weeksUntilQuitDate: Int? = nil
    ) -> TaperInput {
        TaperInput(
            startingCapMg: capMg,
            minutesToFirstUse: minutesToFirstUse,
            usesWhenIllInBed: usesWhenIllInBed,
            weeksUntilQuitDate: weeksUntilQuitDate
        )
    }

    // MARK: - Dependence

    @Test("reaching for it within five minutes reads as heavy, whatever the amount")
    func earlyFirstUseDominates() {
        let plan = TaperPlanner.plan(for: input(capMg: 24, minutesToFirstUse: 3, usesWhenIllInBed: true))
        #expect(plan.dependence == .high)
    }

    @Test("a light, late habit reads as low")
    func lateFirstUseIsLow() {
        let plan = TaperPlanner.plan(for: input(capMg: 6, minutesToFirstUse: 120))
        #expect(plan.dependence == .low)
    }

    // MARK: - Dose

    @Test("patch strength follows intake, the way the licensed labelling does")
    func patchFollowsIntake() {
        #expect(TaperPlanner.plan(for: input(capMg: 24)).replacement.patchMg == 21)
        #expect(TaperPlanner.plan(for: input(capMg: 14)).replacement.patchMg == 14)
        #expect(TaperPlanner.plan(for: input(capMg: 6)).replacement.patchMg == nil)
    }

    @Test("no patch is ever recommended above 21 mg")
    func patchIsCapped() {
        // Going above ~21 mg buys nothing and costs tolerability — treatment
        // withdrawals RR 4.99 — so a very heavy intake must not scale the patch.
        let plan = TaperPlanner.plan(for: input(capMg: 90, minutesToFirstUse: 2, usesWhenIllInBed: true))
        #expect(plan.replacement.patchMg == 21)
    }

    @Test("fast-acting strength follows dependence, not intake")
    func fastActingFollowsDependence() {
        // 4 mg beats 2 mg for dependent users and shows no clear benefit for
        // light ones, so this is keyed to dependence rather than to mg a day.
        #expect(TaperPlanner.plan(for: input(minutesToFirstUse: 3, usesWhenIllInBed: true)).replacement.fastActingMg == 4)
        #expect(TaperPlanner.plan(for: input(capMg: 6, minutesToFirstUse: 120)).replacement.fastActingMg == 2)
    }

    @Test("every plan pairs a fast-acting form with the patch when one is indicated")
    func combinationIsTheDefault() {
        // Combination beats single form, RR 1.27, and is the ceiling this
        // product can reach — so it is the default, not an upsell.
        let plan = TaperPlanner.plan(for: input(capMg: 24))
        #expect(plan.replacement.patchMg != nil)
        #expect(plan.replacement.fastActingMg > 0)
    }

    // MARK: - The descent

    @Test("the cap descends to exactly zero and never rises")
    func descentIsMonotonicToZero() {
        let plan = TaperPlanner.plan(for: input(capMg: 18, weeksUntilQuitDate: 10))
        #expect(plan.weeklyCapsMg.first == 18)
        #expect(plan.weeklyCapsMg.last == 0)
        #expect(zip(plan.weeklyCapsMg, plan.weeklyCapsMg.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test("a heavier habit gets a longer floor than a lighter one")
    func dependenceSetsThePace() {
        // One taper curve cannot fit everyone: dose matters much more to a
        // dependent user, so their descent is not allowed to be as steep.
        // All three ask for the same impossible date, so what differs is only
        // the floor each is allowed to be stretched to. Covering .low as well
        // as .high, because the four-week floor is otherwise never reached.
        let high = TaperPlanner.plan(for: input(capMg: 30, minutesToFirstUse: 2, usesWhenIllInBed: true, weeksUntilQuitDate: 1))
        let moderate = TaperPlanner.plan(for: input(capMg: 30, minutesToFirstUse: 120, weeksUntilQuitDate: 1))
        let low = TaperPlanner.plan(for: input(capMg: 6, minutesToFirstUse: 120, weeksUntilQuitDate: 1))

        #expect(high.dependence == .high)
        #expect(moderate.dependence == .moderate)
        #expect(low.dependence == .low)

        // Week counts are floor + 1, so 8 / 6 / 5 for floors of 7 / 5 / 4.
        #expect(high.weeklyCapsMg.count == 8)
        #expect(moderate.weeklyCapsMg.count == 6)
        #expect(low.weeklyCapsMg.count == 5)
    }

    @Test("a quit date sooner than is safe is stretched, not compressed")
    func tooSoonIsStretched() {
        // Being given a schedule and failing it was associated with worse
        // outcomes than never receiving one, so an unachievable plan must not
        // be issued just because it was asked for.
        let plan = TaperPlanner.plan(for: input(capMg: 30, minutesToFirstUse: 2, usesWhenIllInBed: true, weeksUntilQuitDate: 2))
        #expect(plan.stretchedFromRequestedWeeks == 2)
        #expect(plan.weeklyCapsMg.count > 3)
    }

    @Test("a quit date with room to spare is honoured exactly")
    func generousDateIsKept() {
        let plan = TaperPlanner.plan(for: input(capMg: 12, minutesToFirstUse: 120, weeksUntilQuitDate: 12))
        #expect(plan.stretchedFromRequestedWeeks == nil)
        #expect(plan.weeklyCapsMg.count == 13) // week 0 through the quit week
    }

    @Test("no quit date holds the cap rather than inventing a deadline")
    func reductionOnlyHolds() {
        // A reduction-only user is a supported state, not an incomplete one.
        // Manufacturing a quit date for them is the product addressing the
        // wrong person.
        let plan = TaperPlanner.plan(for: input(capMg: 18, weeksUntilQuitDate: nil))
        #expect(plan.weeklyCapsMg.allSatisfy { $0 == 18 })
        #expect(plan.reachesZero == false)
    }

    // MARK: - Rails

    @Test("an implausible intake is flagged rather than planned around")
    func implausibleIntakeIsFlagged() {
        // Twenty cigarettes a day is 20–40 mg absorbed. A day-one ceiling far
        // above that is a data-entry error, not a heavy user, and a plan built
        // on it would descend from a number that never existed.
        #expect(TaperPlanner.plan(for: input(capMg: 200)).intakeLooksImplausible)
        #expect(TaperPlanner.plan(for: input(capMg: 40)).intakeLooksImplausible == false)
    }

    @Test("a zero or negative starting cap yields no plan at all")
    func nonPositiveIntakeYieldsNothing() {
        #expect(TaperPlanner.plan(for: input(capMg: 0)).weeklyCapsMg.isEmpty)
        #expect(TaperPlanner.plan(for: input(capMg: -5)).weeklyCapsMg.isEmpty)
    }

    @Test("the plan carries no field a view could render as an efficacy claim")
    func noEfficacyClaim() {
        // The taper itself is not established — a small, uncertain,
        // probably-not-harmful benefit — so there must be nothing here for a
        // view to turn into a promise. Asserted structurally rather than by
        // behaviour, because the risk is a field being *added* later; an
        // earlier version of this test checked a week count, which would not
        // have noticed.
        let plan = TaperPlanner.plan(for: input(capMg: 18, weeksUntilQuitDate: 8))
        let fields = Mirror(reflecting: plan).children.compactMap(\.label).map { $0.lowercased() }
        let claimLike = ["success", "efficacy", "odds", "confidence", "likelihood", "probability", "chance"]
        for field in fields {
            #expect(!claimLike.contains { field.contains($0) }, "\(field) invites an efficacy claim")
        }
        #expect(!fields.isEmpty) // guards against the mirror silently returning nothing
    }

    @Test("a starting cap that is not a countable number is rounded from week zero")
    func startingCapIsActionable() {
        // Mixed sources sum to awkward totals. Week zero used to escape the
        // rounding every later week got, so the plan opened on the one figure
        // nobody could act on.
        let plan = TaperPlanner.plan(for: input(capMg: 14.4, weeksUntilQuitDate: 6))
        #expect(plan.weeklyCapsMg.first == 14.5)
        #expect(plan.weeklyCapsMg.allSatisfy { ($0 * 2).rounded() / 2 == $0 })
    }

    @Test("a reduction-only plan describes one held ceiling, not an invented horizon")
    func reductionOnlyHasNoHorizon() {
        let plan = TaperPlanner.plan(for: input(capMg: 18, weeksUntilQuitDate: nil))
        #expect(plan.weeklyCapsMg == [18])
    }
}
