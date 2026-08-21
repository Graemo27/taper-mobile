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

/// Everything a finished run hands over: the row to write, and the pad to seed.
///
/// One value rather than two arguments, because the two are answers to the same
/// tap and must be built from the same reading of the clock. A caller holding
/// them separately is a caller that can pass a draft from one moment and keys
/// from another.
struct CompletedRun: Equatable, Sendable {
    var draft: TaperPlanDraft
    var padKeys: [PadKey]
}

extension OnboardingAnswers {
    /// The plan and the pad, both off the screen the user just agreed to.
    ///
    /// Nil for the same reasons `planDraft(shown:)` is nil — this is that
    /// method plus the pad, and the pad needs nothing the draft does not
    /// already require.
    func completedRun(shown preview: PlanPreview) -> CompletedRun? {
        guard let draft = planDraft(shown: preview) else { return nil }
        // `preview.replacement`, not a freshly built plan. Rebuilding reads the
        // clock again, and a day turning over in the gap would seed a pad from
        // a plan nobody was ever shown.
        return CompletedRun(draft: draft, padKeys: padKeys(with: preview.replacement))
    }
}

extension OnboardingAnswers {
    /// The row for a plan the user has actually been shown, or nil while the
    /// run is still incomplete.
    ///
    /// Takes the preview rather than building a second one. Rebuilding reads
    /// the clock again, and the gap between seeing this screen and agreeing to
    /// it is not a frame — it is however long someone spends deciding, which
    /// can be overnight. A day turning over in that gap re-plans against a
    /// shorter runway, and the row then holds a quit date the user never saw.
    ///
    /// So every figure the plan decided comes off the preview, and the only
    /// value read fresh here is the day the cap starts applying — which is
    /// correctly *now*, because it starts when they say go, not when they were
    /// first shown the screen.
    ///
    /// The preview's existence is itself the proof that a plan could be built;
    /// what remains to check is the answers it does not carry.
    func planDraft(shown preview: PlanPreview) -> TaperPlanDraft? {
        guard hasAnsweredTreatment, let firstUse, let usesWhenIllInBed,
              strengthsAreComplete, startingCapMg > 0 else { return nil }

        return TaperPlanDraft(
            startingCapMg: startingCapMg,
            currentCapMg: preview.capMg,
            capEffectiveFrom: Calendar.current.startOfDay(for: now()),
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
