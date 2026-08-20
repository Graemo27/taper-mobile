import Foundation

/// The onboarding run reduced to the row `taper_plans` holds.
///
/// A separate type from `TaperPlan` on purpose. The planner's output is a whole
/// schedule — every weekly cap, the dependence band, the recommended dose — and
/// almost none of it is stored, because it is all recomputed from the columns
/// here. This is the short list the schema actually keeps, and writing it down
/// once means the store is not the place where "which number goes in that
/// column?" gets decided.
///
/// Every field maps to a column with a check constraint behind it. The schema's
/// own history is the argument for taking those seriously: `current_cap_mg` was
/// created as `> 0` on the assumption that a ceiling of nothing is meaningless,
/// which would have failed to persist every plan with a quit date on the one
/// week that mattered — the quit week, where the cap *is* zero.
struct TaperPlanDraft: Equatable, Sendable {
    /// `starting_cap_mg` — the baseline every later figure is read against.
    /// Written once and then left alone, because a moving baseline makes
    /// progress unfalsifiable.
    var startingCapMg: Double
    /// `current_cap_mg` — the ceiling being lived under right now.
    ///
    /// Taken from the plan's first week rather than from `startingCapMg`. They
    /// are the same number on day one, and the planner is the authority on
    /// whether they stay that way: it already rounds week zero to something
    /// countable, and a draft that copied the raw cap would store a figure the
    /// app never showed anyone.
    var currentCapMg: Double
    /// `cap_effective_from` — the day that ceiling started applying.
    var capEffectiveFrom: Date
    /// `quit_date` — nil for a run holding where it is, which the schema
    /// supports deliberately rather than tolerating.
    var quitDate: Date?
    /// `first_use_minutes` — the strongest single dependence item.
    var firstUseMinutes: Int
    /// `sick_in_bed` — the second.
    var sickInBed: Bool
}

extension OnboardingAnswers {
    /// The run as a row, or nil while it is still incomplete.
    ///
    /// One clock read, shared by the plan, the date stored against it and the
    /// day the cap takes effect. Two reads can straddle midnight, and the
    /// schema has a constraint that notices: `quit_date >= cap_effective_from`
    /// would reject a plan whose start was recorded a day after its end was
    /// computed.
    var planDraft: TaperPlanDraft? {
        let today = now()
        guard hasAnsweredTreatment,
              let input = taperInput(asOf: today),
              let firstUse,
              let usesWhenIllInBed,
              let preview = PlanPreview(
                  plan: TaperPlanner.plan(for: input),
                  today: today,
                  treatments: treatments
              )
        else { return nil }

        return TaperPlanDraft(
            startingCapMg: input.startingCapMg,
            currentCapMg: preview.capMg,
            capEffectiveFrom: Calendar.current.startOfDay(for: today),
            // The date the descent actually reaches, not the one that was asked
            // for. A stretched run's requested date is a day the schedule never
            // arrives at, and O11 already tells the user so — storing the
            // request would leave the database disagreeing with the screen the
            // user agreed to.
            quitDate: preview.quitDate,
            firstUseMinutes: firstUse.minutes,
            sickInBed: usesWhenIllInBed
        )
    }
}
