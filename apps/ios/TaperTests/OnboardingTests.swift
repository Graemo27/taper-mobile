import Foundation
import Testing
@testable import Taper

/// Covers the answer model and the progress arithmetic — the parts of
/// onboarding that can be wrong without looking wrong.
struct OnboardingTests {
    @Test("sources are multi-select, because dual use is the common case")
    func sourcesAreMultiSelect() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.toggle(.vape)
        #expect(answers.sources == [.pouches, .vape])
    }

    @Test("choosing the same source twice clears it rather than duplicating it")
    func toggleIsIdempotent() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.toggle(.pouches)
        #expect(answers.sources.isEmpty)
        #expect(answers.hasChosenSources == false)
    }

    @Test("the run cannot continue until something is named")
    func continueRequiresAnAnswer() {
        // The starting cap is summed across the sources named here, so an empty
        // answer is not "no nicotine" — it is a cap of zero, which the planner
        // correctly refuses to build a taper from.
        let answers = OnboardingAnswers()
        #expect(answers.hasChosenSources == false)
        answers.toggle(.cigarettes)
        #expect(answers.hasChosenSources)
    }

    @Test("licensed forms are listed as things to quit, not filtered out")
    func nrtCanBeQuit() {
        // Someone can arrive already on gum and want off it. Treatment is asked
        // separately, and the two must not be inferred from each other.
        #expect(NicotineSource.allCases.contains(.nrt))
        #expect(NicotineSource.nrt.label == "Nicotine gum or lozenges")
    }

    // MARK: - Progress

    @Test("a completed section fills, the current one part-fills, later ones stay empty")
    func progressFillsPerSection() {
        let progress = OnboardingProgress(section: 1, sectionCount: 3, fraction: 0.5)
        let bar = OnboardingProgressBar(progress: progress)
        #expect(bar.fillForTesting(0) == 1)
        #expect(bar.fillForTesting(1) == 0.5)
        #expect(bar.fillForTesting(2) == 0)
    }

    @Test("a fraction outside 0...1 cannot overflow or reverse its segment")
    func progressFractionIsClamped() {
        let over = OnboardingProgressBar(
            progress: OnboardingProgress(section: 0, sectionCount: 3, fraction: 1.8)
        )
        let under = OnboardingProgressBar(
            progress: OnboardingProgress(section: 0, sectionCount: 3, fraction: -0.4)
        )
        #expect(over.fillForTesting(0) == 1)
        #expect(under.fillForTesting(0) == 0)
    }
}

/// Covers the sequence itself — that every step has a place in the run, and
/// that the progress it reports is derived rather than typed in per screen.
struct OnboardingStepTests {
    @Test("the run is twelve steps in three sections of four")
    func sequenceIsWholeAndDivisible() {
        // The indicator shows three segments by design, matching the Paper
        // board, and each covers four screens. Twelve ticks on one track reads
        // as barely moving, which is the opposite of the point.
        #expect(OnboardingStep.allCases.count == 12)
        #expect(OnboardingStep.allCases.count % OnboardingProgress.sections == 0)
    }

    @Test("progress advances section by section across the whole run")
    func progressIsDerivedFromPosition() {
        #expect(OnboardingStep.whatYouUse.progress.section == 0)
        #expect(OnboardingStep.firstUse.progress.section == 0)
        #expect(OnboardingStep.sickInBed.progress.section == 1)
        #expect(OnboardingStep.triedBefore.progress.section == 2)
        #expect(OnboardingStep.planPreview.progress.section == 2)
    }

    @Test("the first step of a section part-fills it and the last completes it")
    func fractionSpansItsSection() {
        #expect(OnboardingStep.whatYouUse.progress.fraction == 0.25)
        #expect(OnboardingStep.firstUse.progress.fraction == 1)
        #expect(OnboardingStep.planPreview.progress.fraction == 1)
    }

    @Test("every step has a successor except the last")
    func sequenceTerminates() {
        for step in OnboardingStep.allCases where step != .planPreview {
            #expect(step.next != nil, "\(step) leads nowhere")
        }
        #expect(OnboardingStep.planPreview.next == nil)
    }
}

/// Covers the strength answer, whose whole subtlety is that "not sure" has to
/// produce a usable number without pretending the user supplied it.
struct StrengthTests {
    @Test("a stated strength is used as given")
    func statedStrengthIsUsed() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 6 }
        #expect(answers.strengthMgPerUnit(for: .pouches) == 6)
        #expect(answers.strengthIsAssumed(for: .pouches) == false)
    }

    @Test("not sure still yields a number, and is flagged as assumed")
    func unsureResolvesButIsFlagged() {
        // Refusing to continue until someone fetches a tin is how a run gets
        // abandoned — but a number the app invented must not be presented back
        // as one the user gave.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == nil }
        #expect(answers.strengthMgPerUnit(for: .pouches) == 3)
        #expect(answers.strengthIsAssumed(for: .pouches))
    }

    @Test("an unanswered question yields nothing at all")
    func unansweredIsNil() {
        let answers = OnboardingAnswers()
        #expect(answers.strengthMgPerUnit(for: .pouches) == nil)
        // Not "assumed" either — nothing has been assumed yet.
        #expect(answers.strengthIsAssumed(for: .pouches) == false)
    }

    @Test("the assumed value is one the matching picker actually offers")
    func assumptionMatchesAnOffer() {
        // The helper text names this number. If it drifted from the options the
        // screen would promise one thing and the arithmetic do another — and an
        // assumption must always be an answer the user could have given.
        #expect(StrengthOption.pouch.contains { $0.mg == StrengthOption.assumedWhenUnsure(for: .pouches) })
        #expect(StrengthOption.nrt.contains { $0.mg == StrengthOption.assumedWhenUnsure(for: .nrt) })
    }

    @Test("exactly one option is the unsure one, in every set")
    func oneUnsureOption() {
        for set in [StrengthOption.pouch, StrengthOption.nrt] {
            #expect(set.filter { $0.mg == nil }.count == 1)
            #expect(set.last?.mg == nil, "unsure belongs at the end, after the real answers")
        }
    }

    @Test("every strength survives being formatted for display")
    func strengthsFormatLosslessly() {
        // The screen prints these and the planner uses them, so a formatter
        // that loses precision makes the two disagree — 1.5 mg reading as
        // "1 mg" while the plan is built on 1.5. Integer truncation passes
        // unnoticed today because 3 and 2 are whole; the lozenge set is where
        // it would bite.
        for option in StrengthOption.pouch + StrengthOption.nrt {
            guard let mg = option.mg else { continue }
            #expect(Double(mg.clean) == mg, "\(mg) formats as \(mg.clean)")
        }
        #expect(1.5.clean == "1.5")
        #expect(3.0.clean == "3")
    }

    @Test("a gum user is only offered strengths gum is sold in")
    func nrtSetMatchesTheProduct() {
        // 3 and 6 mg are pouch strengths; every option must be an answer
        // someone could read off a pack.
        #expect(StrengthOption.options(for: .nrt) == StrengthOption.nrt)
        #expect(!StrengthOption.nrt.contains { $0.mg == 3 || $0.mg == 6 })
        #expect(StrengthOption.nrt.contains { $0.mg == 1.5 })
    }

    @Test("deselecting the last per-unit source clears its strength answer")
    func staleStrengthIsCleared() {
        // The routing skips the screen for a cigarette-only run, so a stale
        // answer would never be shown or corrected — just used.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.isAtLeast }
        answers.exactStrengths[.pouches] = 12
        answers.toggle(.pouches)
        answers.toggle(.cigarettes)
        #expect(answers.strengths.isEmpty)
        #expect(answers.exactStrengths.isEmpty)
        #expect(answers.strengthMgPerUnit(for: .pouches) == nil)
    }

    @Test("a strength survives a source change that keeps its basis")
    func strengthSurvivesWhileBasisRemains() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.toggle(.cigarettes)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 6 }
        answers.toggle(.cigarettes)
        #expect(answers.strengthMgPerUnit(for: .pouches) == 6)
    }
}

/// Covers the two review findings: an open-ended strength must not be planned
/// on as an exact value, and the question must not be asked of a source that
/// cannot answer it.
struct StrengthRangeTests {
    private func atLeastEight() -> StrengthOption {
        StrengthOption.pouch.first { $0.isAtLeast }!
    }

    @Test("an unnarrowed floor does not pass as a stated strength")
    func floorIsNotAStatedValue() {
        // Planning on 8 for a 12 mg pouch sets a cap below what the user
        // actually uses — one they blow on day one, which the evidence says is
        // worse than never being given a schedule.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = atLeastEight()
        #expect(answers.strengthIsAssumed(for: .pouches))
        #expect(answers.sourcesNeedingExactStrength == [.pouches])
    }

    @Test("the run cannot continue on a floor alone")
    func floorBlocksContinue() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = atLeastEight()
        #expect(answers.sourcesNeedingExactStrength == [.pouches])
        answers.exactStrengths[.pouches] = 12
        #expect(answers.sourcesNeedingExactStrength.isEmpty)
        #expect(answers.strengthMgPerUnit(for: .pouches) == 12)
        #expect(answers.strengthIsAssumed(for: .pouches) == false)
    }

    @Test("an exact figure only applies to the open-ended option")
    func exactIgnoredForClosedOptions() {
        // A stale value left over from a previous answer must not override a
        // strength the user has since stated plainly.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.exactStrengths[.pouches] = 12
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 2 }
        #expect(answers.strengthMgPerUnit(for: .pouches) == 2)
    }

    @Test("only sources with a printed per-piece figure are asked")
    func strengthAppliesPerSource() {
        // A cigarette's dose is a property of the cigarette, not a choice, and
        // a vape is mg/mL against unmeasured puffs. Asking either would make
        // the user invent a number the plan is then built on.
        #expect(NicotineSource.pouches.usesPerUnitStrength)
        #expect(NicotineSource.nrt.usesPerUnitStrength)
        for source in [NicotineSource.cigarettes, .vape, .dip, .other] {
            #expect(source.usesPerUnitStrength == false, "\(source) has no per-piece figure to pick")
        }
    }
}

/// Covers the amounts screen: each source counted in its own unit, and a
/// starting figure that is an index rather than a measurement.
struct AmountTests {
    @Test("each source is counted in a unit its user actually knows")
    func unitsAreNative() {
        #expect(NicotineSource.vape.unitLabel == "Puffs a day")
        #expect(NicotineSource.cigarettes.unitLabel == "Cigarettes a day")
        #expect(NicotineSource.dip.unitLabel == "Packs a day")
        // Nobody is asked for milligrams they cannot read off a pack.
        for source in NicotineSource.allCases {
            #expect(!source.unitLabel.lowercased().contains("mg"))
        }
    }

    @Test("puffs step in fives, everything else in ones")
    func stepMatchesTheUnit() {
        // Puffs run to dozens; stepping one at a time would make the honest
        // answer the tedious one.
        #expect(NicotineSource.vape.step == 5)
        for source in NicotineSource.allCases where source != .vape {
            #expect(source.step == 1)
        }
    }

    @Test("only sources with nothing printed carry an estimate")
    func estimatesOnlyWhereNothingIsPrinted() {
        // A pouch and a lozenge print their strength, so the user tells us.
        #expect(NicotineSource.pouches.estimatedMgPerUnit == nil)
        #expect(NicotineSource.nrt.estimatedMgPerUnit == nil)
        for source in [NicotineSource.cigarettes, .vape, .dip, .other] {
            #expect(source.estimatedMgPerUnit != nil)
        }
    }

    @Test("the cigarette estimate matches the only benchmark the vault holds")
    func cigaretteEstimateIsSourced() {
        // 20 a day absorbing 20–40 mg puts one cigarette at 1–2 mg; 1.5 is the
        // midpoint consistent with both figures in nicotine-dose-reference.
        let perUnit = NicotineSource.cigarettes.estimatedMgPerUnit!
        #expect(perUnit * 20 >= 20)
        #expect(perUnit * 20 <= 40)
    }

    @Test("pouches and gum each keep their own printed strength")
    func mixedPrintedStrengthsStaySeparate() {
        // The bug this replaced: one answer applied to both, so a 6 mg pouch
        // made gum count as 6 mg — a strength gum is not sold in.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.toggle(.nrt)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 6 }
        answers.strengths[.nrt] = StrengthOption.nrt.first { $0.mg == 2 }
        answers.setAmount(5, for: .pouches)   // 30
        answers.setAmount(4, for: .nrt)       // 8
        #expect(answers.strengthMgPerUnit(for: .pouches) == 6)
        #expect(answers.strengthMgPerUnit(for: .nrt) == 2)
        #expect(answers.startingCapMg == 38)
    }

    @Test("each source is offered only the strengths its own product comes in")
    func optionsAreKeyedToTheSource() {
        #expect(StrengthOption.options(for: .pouches) == StrengthOption.pouch)
        #expect(StrengthOption.options(for: .nrt) == StrengthOption.nrt)
    }

    @Test("an unsure answer resolves per product, not per run")
    func unsureIsPerSource() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.toggle(.nrt)
        answers.strengths[.pouches] = StrengthOption.pouch.last  // not sure
        answers.strengths[.nrt] = StrengthOption.nrt.last        // not sure
        #expect(answers.strengthMgPerUnit(for: .pouches) == 3)
        #expect(answers.strengthMgPerUnit(for: .nrt) == 2)
    }

    @Test("a floor narrowed for one source does not narrow the other")
    func exactStrengthIsPerSource() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.toggle(.nrt)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.isAtLeast }
        answers.strengths[.nrt] = StrengthOption.nrt.first { $0.mg == 4 }
        #expect(answers.sourcesNeedingExactStrength == [.pouches])
        answers.exactStrengths[.pouches] = 12
        #expect(answers.sourcesNeedingExactStrength.isEmpty)
        #expect(answers.strengthMgPerUnit(for: .pouches) == 12)
        #expect(answers.strengthMgPerUnit(for: .nrt) == 4)
    }

    @Test("a printed strength is used for pouches, not an estimate")
    func printedStrengthWins() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 6 }
        answers.setAmount(5, for: .pouches)
        #expect(answers.startingCapMg == 30)
    }

    @Test("sources sum, each through its own conversion")
    func sourcesSum() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.toggle(.cigarettes)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(6, for: .pouches)      // 18 label mg
        answers.setAmount(10, for: .cigarettes)  // 15 estimated mg
        #expect(answers.startingCapMg == 33)
    }

    @Test("deselecting a source stops it counting from off-screen")
    func amountsFollowSources() {
        let answers = OnboardingAnswers()
        answers.toggle(.cigarettes)
        answers.setAmount(20, for: .cigarettes)
        #expect(answers.startingCapMg == 30)
        answers.toggle(.cigarettes)
        #expect(answers.amounts.isEmpty)
        #expect(answers.startingCapMg == 0)
    }

    @Test("rows keep a stable order rather than a set's arbitrary one")
    func orderIsStable() {
        // Rows that reshuffle between renders are unusable.
        let answers = OnboardingAnswers()
        answers.toggle(.dip)
        answers.toggle(.pouches)
        answers.toggle(.vape)
        #expect(answers.orderedSources == [.pouches, .vape, .dip])
    }

    @Test("an amount cannot go below zero")
    func amountHasAFloor() {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.setAmount(-4, for: .pouches)
        #expect(answers.amount(for: .pouches) == 0)
    }

    @Test("an unanswered source starts at a plausible middle, not at zero")
    func defaultsAreUsable() {
        let answers = OnboardingAnswers()
        answers.toggle(.vape)
        #expect(answers.amount(for: .vape) == 40)
        #expect(answers.amount(for: .vape) % NicotineSource.vape.step == 0)
    }
}

/// Covers O4, whose risk is not the screen but the join to the planner: the
/// wording promises the answer sizes the steps, so each option has to land in
/// the dependence band its words imply.
struct FirstUseTests {
    private func plan(_ option: FirstUseOption, capMg: Double = 12) -> TaperPlan {
        TaperPlanner.plan(for: TaperInput(
            startingCapMg: capMg,
            minutesToFirstUse: option.minutes,
            usesWhenIllInBed: false,
            weeksUntilQuitDate: 1
        ))
    }

    private func option(_ label: String) -> FirstUseOption {
        FirstUseOption.all.first { $0.label == label }!
    }

    @Test("reaching for it on waking reads as high dependence on its own")
    func firstThingIsHigh() {
        // The strongest single item in the index, and sufficient by itself —
        // a light daily total must not outvote it.
        #expect(plan(option("It's the first thing I do"), capMg: 6).dependence == .high)
    }

    @Test("an afternoon habit does not")
    func afternoonIsNotHigh() {
        #expect(plan(option("Afternoon or later"), capMg: 6).dependence == .low)
    }

    @Test("the options run from most to least dependent, without ties")
    func optionsAreOrderedAndDistinct() {
        // Ordered because the list reads as a scale; distinct because two
        // options resolving to the same minutes would be two ways to say one
        // thing, which is a question with a redundant answer.
        let minutes = FirstUseOption.all.map(\.minutes)
        #expect(minutes == minutes.sorted())
        #expect(Set(minutes).count == minutes.count)
    }

    @Test("each option sits inside its band, not on the edge")
    func valuesAreNotOnThresholds() {
        // 20 rather than 30 for "within 30 minutes", so shifting a threshold
        // later cannot silently reclassify an answer someone already gave.
        for boundary in [6, 31, 61] {
            #expect(!FirstUseOption.all.contains { $0.minutes == boundary })
            #expect(!FirstUseOption.all.contains { $0.minutes == boundary - 1 })
        }
    }

    @Test("answering moves the plan's floor, which is what the helper promises")
    func theAnswerChangesTheSchedule() {
        // "This sizes your steps" has to be true, or the copy is a claim the
        // product does not honour.
        let earliest = plan(option("It's the first thing I do"), capMg: 24)
        let latest = plan(option("Afternoon or later"), capMg: 24)
        #expect(earliest.weeklyCapsMg.count > latest.weeklyCapsMg.count)
    }
}

/// Covers O5, whose risk is that a yes/no with an obvious-sounding answer is
/// easy to store as a plain `Bool` and quietly default. It is the second of the
/// two dependence items, so a default here is a plan built on a claim the user
/// never made.
struct SickInBedTests {
    /// A run that sits one point under high without this item, so the answer
    /// is what decides the band. A quit date is set because a reduction-only
    /// plan holds a single cap and would hide the difference entirely.
    private func plan(illInBed: Bool, minutes: Int = 20) -> TaperPlan {
        TaperPlanner.plan(for: TaperInput(
            startingCapMg: 24,
            minutesToFirstUse: minutes,
            usesWhenIllInBed: illInBed,
            weeksUntilQuitDate: 1
        ))
    }

    @Test("the question starts unanswered rather than answered no")
    func startsNil() {
        // A plain Bool would open on false, which is one of the two answers.
        // Nobody has said it yet, and the bridge has to be able to tell.
        #expect(OnboardingAnswers().usesWhenIllInBed == nil)
    }

    @Test("the run cannot continue past a question nobody answered")
    func continueRequiresAnAnswer() {
        // There is no skip, and no answer this screen can assume on someone's
        // behalf. Walking past it is silent: the run would reach the plan
        // preview with an input that can never resolve, and the first sign of
        // trouble would be the last screen having nothing to show.
        let answers = OnboardingAnswers()
        #expect(answers.hasAnsweredSickInBed == false)
        for option in SickInBedOption.all {
            answers.usesWhenIllInBed = option.stillUses
            #expect(answers.hasAnsweredSickInBed)
        }
    }

    @Test("the yes row means yes")
    func labelsMatchTheValuesTheyStandFor() {
        // The one thing a reviewer cannot catch by looking at the screen: both
        // rows render fine either way round, and a swap scores someone a whole
        // band higher on an answer they did not give.
        #expect(SickInBedOption.all.first { $0.label == "Yep" }?.stillUses == true)
        #expect(SickInBedOption.all.first { $0.label == "Nope!" }?.stillUses == false)
        #expect(SickInBedOption.all.map(\.stillUses) == [true, false])
    }

    @Test("both taps are recorded, and either can be changed to the other")
    func bothAnswersStick() {
        let answers = OnboardingAnswers()
        for option in SickInBedOption.all {
            answers.usesWhenIllInBed = option.stillUses
            #expect(answers.usesWhenIllInBed == option.stillUses)
        }
    }

    @Test("using through illness lengthens the descent, which is why it is asked")
    func theAnswerChangesTheSchedule() {
        // The screen spends a question on this, so it has to move the plan.
        // If it did not, the honest change would be to delete the screen.
        #expect(plan(illInBed: true).dependence == .high)
        #expect(plan(illInBed: false).dependence == .moderate)
        #expect(plan(illInBed: true).weeklyCapsMg.count > plan(illInBed: false).weeklyCapsMg.count)
    }

    @Test("it cannot outvote the strongest item on its own")
    func doesNotOverrideFirstUse() {
        // Reaching for it on waking is high dependence by itself. Answering
        // "no" here must not talk that back down — the index weights the two
        // items, it does not average them.
        #expect(plan(illInBed: false, minutes: 3).dependence == .high)
    }
}

/// Covers the seam between what onboarding collects and what the planner takes.
///
/// The mapping is the risk: `minutesToFirstUse` is a number the user never sees
/// and never types, so nothing on screen would look wrong if it were wired to
/// the wrong option.
struct TaperInputBridgeTests {
    private func answered() -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(6, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
        answers.usesWhenIllInBed = true
        return answers
    }

    @Test("a complete run maps every answer to the field the planner reads")
    func completeRunMaps() {
        let input = answered().taperInput
        #expect(input?.startingCapMg == 18)
        #expect(input?.minutesToFirstUse == 20)
        #expect(input?.usesWhenIllInBed == true)
        // Reduction-only is a supported state, not a missing answer.
        #expect(input?.weeksUntilQuitDate == nil)
    }

    @Test("an unanswered question yields no input rather than a default")
    func incompleteRunYieldsNothing() {
        // There is no default here that would not be an invention. A plan built
        // partly on values nobody supplied is the failure this flow is shaped
        // to avoid, so the bridge refuses rather than filling gaps.
        let noFirstUse = answered(); noFirstUse.firstUse = nil
        #expect(noFirstUse.taperInput == nil)

        let noSickInBed = answered(); noSickInBed.usesWhenIllInBed = nil
        #expect(noSickInBed.taperInput == nil)

        let noAmount = answered(); noAmount.setAmount(0, for: .pouches)
        #expect(noAmount.taperInput == nil)
    }

    @Test("a cap that leaves out a named source is not a cap")
    func aPartlyAnsweredMixedRunYieldsNothing() {
        // Cigarettes need no strength question, so they carry the cap on their
        // own. That makes the total positive while the pouches the user also
        // named contribute nothing — a figure that looks whole and is short by
        // a whole product. The bridge has to refuse it, because the screen
        // downstream cannot tell the difference.
        let answers = answered()
        answers.toggle(.cigarettes)
        answers.setAmount(10, for: .cigarettes)
        answers.strengths[.pouches] = nil
        #expect(answers.startingCapMg > 0)
        #expect(answers.taperInput == nil)

        // Answering it completes the run, and the cap now includes both.
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        #expect(answers.taperInput?.startingCapMg == 33)
    }

    @Test("a floor is not a strength")
    func anUnNarrowedFloorYieldsNothing() {
        // "8 mg or more" is the one answer that plans low: taking the floor
        // would size the cap for 8 when the tin might say 12.
        let answers = answered()
        answers.strengths[.pouches] = StrengthOption.pouch.first(where: \.isAtLeast)
        #expect(answers.taperInput == nil)

        answers.exactStrengths[.pouches] = 12
        #expect(answers.taperInput?.startingCapMg == 72)
    }

    @Test("answering no is not the same as not answering")
    func falseIsAnAnswer() {
        let answers = answered()
        answers.usesWhenIllInBed = false
        #expect(answers.taperInput?.usesWhenIllInBed == false)
        #expect(answers.taperInput != nil)
    }

    @Test("the answer the user gave is the one the plan is built from")
    func theBridgeCarriesTheAnswerThrough() {
        // End to end: pick the earliest band, and the plan that comes out the
        // far side is the dependent one. Nothing on screen would look wrong if
        // this were miswired, which is why it is asserted here.
        let answers = answered()
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 3 }
        let plan = answers.taperInput.map(TaperPlanner.plan(for:))
        #expect(plan?.dependence == .high)
    }
}

/// Covers O5a, where the app stops asking and starts recommending.
///
/// Two risks, both of them the screen telling the user something the product
/// does not actually stand behind: a dose shown here that the plan does not
/// use, and a claim stronger than the evidence it rests on.
struct TreatmentTests {
    private func answers(pouches: Int = 10, strengthMg: Double = 3, minutes: Int = 20) -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == strengthMg }
        answers.setAmount(pouches, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == minutes }
        answers.usesWhenIllInBed = true
        return answers
    }

    @Test("only forms someone can actually get are offered")
    func noPrescriptionOnlyForms() {
        // The schema carries inhaler and spray because a user may already be on
        // one. Offering them here would be a dead end dressed as a choice — and
        // every option on this screen is one the app is recommending.
        #expect(TreatmentForm.allCases.map(\.rawValue) == ["patch", "lozenge", "gum"])
    }

    @Test("every strength shown is one the plan committed to")
    func strengthsComeFromThePlan() {
        // The screen is not allowed its own numbers. A 21 mg patch printed here
        // beside a plan built on 14 is a recommendation the product does not
        // stand behind, and nothing downstream would contradict it.
        let answers = answers()
        let plan = TaperPlanner.plan(for: answers.taperInput!)
        let suggestion = answers.treatmentSuggestion!
        #expect(suggestion.strengthMg[.patch] == plan.replacement.patchMg)
        #expect(suggestion.strengthMg[.lozenge] == plan.replacement.fastActingMg)
        #expect(suggestion.strengthMg[.gum] == plan.replacement.fastActingMg)
    }

    @Test("a light intake is suggested one product, with no patch strength")
    func lightIntakeGetsNoPatch() {
        // Below the threshold the planner warrants no patch. Listing one with a
        // strength attached would recommend it by implication.
        let light = answers(pouches: 2, strengthMg: 2)
        let suggestion = light.treatmentSuggestion!
        #expect(suggestion.forms == [.lozenge])
        #expect(suggestion.strengthMg[.patch] == nil)
    }

    @Test("the combination claim is made only about the combination")
    func evidenceOnlyWhereItApplies() {
        // The evidence compares two products against one. Repeating it beside a
        // single-product suggestion would attach a finding to something it did
        // not measure.
        #expect(answers().treatmentSuggestion?.evidence != nil)
        #expect(answers(pouches: 2, strengthMg: 2).treatmentSuggestion?.evidence == nil)
    }

    @Test("the claim states the estimate, not the top of its interval")
    func evidenceIsNotRoundedUp() {
        // RR 1.27 (1.17–1.37). "About a third" reads the ceiling as the
        // estimate, which is the one direction a health claim must not drift.
        let claim = answers().treatmentSuggestion?.evidence ?? ""
        #expect(claim.contains("a quarter"))
        #expect(!claim.contains("a third"))
    }

    @Test("the suggestion reads the user's own answers back")
    func basisRestatesTheRun() {
        // 10 pouches at 3 mg, first one within 30 minutes — both figures are
        // the user's, and the sentence has to be the one they would recognise.
        #expect(answers().treatmentSuggestion?.basis == "30 mg a day, first one inside 30 minutes of waking.")
    }

    @Test("every first-use answer has a recap that reads in the sentence")
    func everyRecapFits() {
        // The recap is a second wording of an answer already given. One that
        // does not fit produces a sentence about a band the user did not pick.
        for option in FirstUseOption.all {
            #expect(!option.recap.isEmpty)
            #expect(option.recap.first?.isUppercase == false)
            #expect(!option.recap.hasSuffix("."))
        }
        #expect(Set(FirstUseOption.all.map(\.recap)).count == FirstUseOption.all.count)
    }

    @Test("a half-answered run has nothing to suggest")
    func incompleteRunSuggestsNothing() {
        let answers = answers()
        answers.firstUse = nil
        #expect(answers.treatmentSuggestion == nil)
    }

    @Test("declining and choosing are answers; silence is not")
    func theQuestionHasThreeStates() {
        let answers = OnboardingAnswers()
        #expect(answers.hasAnsweredTreatment == false)
        answers.toggle(.patch)
        #expect(answers.hasAnsweredTreatment)
        answers.deferTreatment()
        #expect(answers.hasAnsweredTreatment)
        #expect(answers.treatments.isEmpty)
    }

    @Test("choosing and declining cannot both be true at once")
    func theTwoAnswersCancel() {
        // They are contradictory answers to one question. Holding both would
        // let the run continue on whichever the next screen happened to read.
        let answers = OnboardingAnswers()
        answers.deferTreatment()
        answers.toggle(.patch)
        #expect(answers.defersTreatment == false)
        #expect(answers.treatments == [.patch])

        answers.deferTreatment()
        #expect(answers.defersTreatment)
        #expect(answers.treatments.isEmpty)
    }

    @Test("no sequence of taps can hold both answers at once")
    func theInvariantSurvivesAnyOrder() {
        // The pairwise check above covers the order I thought of. This covers
        // the ones I did not: every route through the screen, three taps deep.
        // `treatments` is write-restricted so these are the only routes there
        // are — a direct insert would walk past the invariant, and would not
        // compile.
        enum Tap: CaseIterable {
            case patch, lozenge, gum, decline
        }

        for first in Tap.allCases {
            for second in Tap.allCases {
                for third in Tap.allCases {
                    let answers = OnboardingAnswers()
                    for tap in [first, second, third] {
                        switch tap {
                        case .patch: answers.toggle(.patch)
                        case .lozenge: answers.toggle(.lozenge)
                        case .gum: answers.toggle(.gum)
                        case .decline: answers.deferTreatment()
                        }
                    }
                    #expect(
                        !(answers.defersTreatment && !answers.treatments.isEmpty),
                        "\(first)/\(second)/\(third) left both answers standing"
                    )
                }
            }
        }
    }

    @Test("a patch and a fast-acting form can be held together")
    func combinationIsSelectable() {
        // The whole point of the screen: combination is the default shape, so
        // the control has to allow it rather than treating forms as exclusive.
        let answers = OnboardingAnswers()
        answers.toggle(.patch)
        answers.toggle(.lozenge)
        #expect(answers.treatments == [.patch, .lozenge])
        answers.toggle(.lozenge)
        #expect(answers.treatments == [.patch])
    }
}

/// Covers the copy O5a puts on screen, which is where a recommendation turns
/// into sentences. The rows quote strengths, so the join between the number the
/// planner chose and the number the user reads is the thing worth pinning.
struct TreatmentCopyTests {
    private func suggestion(pouches: Int = 10) -> TreatmentSuggestion {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(pouches, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
        answers.usesWhenIllInBed = true
        return answers.treatmentSuggestion!
    }

    @Test("a row quotes the strength this plan uses, not a typical one")
    func rowsQuoteThePlan() {
        let suggestion = suggestion()
        #expect(suggestion.detail(for: .patch) == "21 mg, 24 hours · the steady floor")
        #expect(suggestion.detail(for: .lozenge) == "4 mg · for the moment a craving lands")
        #expect(suggestion.detail(for: .gum) == "4 mg · instead of the lozenge")
    }

    @Test("a form the plan has no dose for is described without one")
    func noDoseMeansNoNumber() {
        // The row still appears — someone may want a patch anyway — but a
        // strength printed beside it would be the app recommending a dose it
        // did not choose.
        let light = suggestion(pouches: 2)
        #expect(light.strengthMg[.patch] == nil)
        #expect(light.detail(for: .patch) == "the steady floor")
        #expect(!light.detail(for: .patch).contains("mg"))
    }

    @Test("the blurb states the user's own figures before any claim")
    func blurbLeadsWithTheirAnswers() {
        // Order matters: their numbers first, so the suggestion reads as a
        // consequence of what they said rather than a statistic with a
        // preference attached.
        let blurb = suggestion().blurb
        #expect(blurb.hasPrefix("30 mg a day, first one inside 30 minutes of waking."))
        #expect(blurb.hasSuffix("about a quarter more people get there."))
    }

    @Test("a single-form suggestion carries no claim at all")
    func lightRunHasNoClaim() {
        #expect(suggestion(pouches: 2).blurb == "6 mg a day, first one inside 30 minutes of waking.")
    }

    @Test("the headline names what is actually being suggested")
    func headlineMatchesTheForms() {
        #expect(suggestion().headline == "A patch and a lozenge")
        #expect(suggestion(pouches: 2).headline == "A lozenge")
    }
}

/// Covers O6, the one screen that asks nothing and only asserts.
///
/// Its whole claim on the user's trust is that every part of it is either
/// something they said or something the plan actually does. A sentence here
/// that is neither is the screen quietly making things up about them.
struct StartingLineTests {
    private func answers(pouches: Int = 6, minutes: Int = 20) -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(pouches, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == minutes }
        answers.usesWhenIllInBed = true
        return answers
    }

    @Test("the number named is the one the run produced")
    func headlineMatchesTheCap() {
        #expect(answers().startingLine?.headline == "Your starting line: 18 mg a day.")
        #expect(answers(pouches: 10).startingLine?.headline == "Your starting line: 30 mg a day.")
    }

    @Test("week one is read from the plan, not asserted alongside it")
    func weekOneComesFromThePlan() {
        // The sentence promises week one holds at the starting figure. They are
        // the same number today; if the planner ever adjusts the first week, the
        // copy has to move with it rather than keep describing the old
        // behaviour.
        let answers = answers(pouches: 7)
        let weekOne = TaperPlanner.plan(for: answers.taperInput!).weeklyCapsMg.first!
        #expect(answers.startingLine?.body.contains("holds steady at \(weekOne.clean) mg") == true)
    }

    @Test("the screen says nothing about triggers, which have not been asked yet")
    func noTriggersBeforeTheyAreAsked() {
        // The board's copy names them — "mostly with coffee and stress" — but
        // `.triggers` is the next step, so anything said here would be invented
        // about a user who has not answered.
        #expect(OnboardingStep.startingLine.rawValue < OnboardingStep.triggers.rawValue)
        let body = answers().startingLine?.body ?? ""
        #expect(!body.contains("coffee"))
        #expect(!body.contains("stress"))
    }

    @Test("it reads the user's own first-use answer back")
    func bodyQuotesTheirAnswer() {
        #expect(answers(minutes: 3).startingLine?.body.hasPrefix("Your first one is before anything else.") == true)
        #expect(answers(minutes: 360).startingLine?.body.hasPrefix("Your first one is in the afternoon or later.") == true)
    }

    @Test("a half-answered run produces no summary to show")
    func incompleteRunHasNoLine() {
        let answers = answers()
        answers.usesWhenIllInBed = nil
        #expect(answers.startingLine == nil)
    }

    @Test("a run with no plan to describe produces nothing rather than an empty claim")
    func noPlanMeansNoLine() {
        // weeklyCapsMg is empty when there is no cap to descend from. A summary
        // built anyway would promise a week one that does not exist.
        let plan = TaperPlanner.plan(for: TaperInput(
            startingCapMg: 0,
            minutesToFirstUse: 20,
            usesWhenIllInBed: false,
            weeksUntilQuitDate: nil
        ))
        #expect(plan.weeklyCapsMg.isEmpty)
        #expect(StartingLine(plan: plan, dailyMg: 0, firstUse: FirstUseOption.all[0]) == nil)
    }
}

/// Covers O7. The risk here is the opposite of every other screen's: not a
/// fabricated number, but a question gated so that someone whose moments are
/// not on the list has to tick a false one to get past it.
struct TriggerTests {
    @Test("the moments are situations, not states to be interpreted")
    func triggersAreSituations() {
        // "Stress" alone asks someone to interpret themselves before they can
        // answer. Work stress and driving either happened or did not.
        #expect(Trigger.allCases.count == 6)
        #expect(Trigger.allCases.map(\.label).allSatisfy { !$0.isEmpty })
        #expect(Set(Trigger.allCases.map(\.label)).count == Trigger.allCases.count)
    }

    @Test("several can be held at once, because most people have several")
    func triggersAreMultiSelect() {
        let answers = OnboardingAnswers()
        answers.toggle(Trigger.work)
        answers.toggle(Trigger.driving)
        #expect(answers.triggers == [.work, .driving])
        answers.toggle(Trigger.work)
        #expect(answers.triggers == [.driving])
    }

    @Test("rows keep a stable order rather than a set's arbitrary one")
    func orderIsStable() {
        let answers = OnboardingAnswers()
        answers.toggle(Trigger.boredom)
        answers.toggle(Trigger.drinks)
        #expect(answers.orderedTriggers == [.drinks, .boredom])
    }

    @Test("naming nothing is a permitted answer")
    func noTriggerIsRequired() {
        // The one ungated question in the run. Requiring a selection would make
        // someone whose moments are not listed tick one that is false — the
        // same fabrication the strength screen exists to avoid, in categorical
        // form. Nothing downstream reads these as a number, so "none of these",
        // "none at all" and "did not say" can safely behave alike.
        let answers = OnboardingAnswers()
        #expect(answers.triggers.isEmpty)
        #expect(answers.orderedTriggers.isEmpty)
    }

    @Test("triggers reach no plan, so they cannot move one")
    func triggersDoNotAffectThePlan() {
        // They are context for the craving screen, not a dependence item. If
        // ticking one ever changed the schedule, the screen would be quietly
        // scoring people on an answer presented as optional.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(6, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
        answers.usesWhenIllInBed = true

        let before = TaperPlanner.plan(for: answers.taperInput!)
        Trigger.allCases.forEach { answers.toggle($0) }
        let after = TaperPlanner.plan(for: answers.taperInput!)

        #expect(before.dependence == after.dependence)
        #expect(before.weeklyCapsMg == after.weeklyCapsMg)
    }
}

/// Covers O8. Two things to hold: the exclusive answer stays exclusive from
/// either direction, and nothing here reaches the plan — the helper promises
/// there are no wrong answers, and a screen that scored people would be
/// contradicting the sentence that got them to answer honestly.
struct PriorAttemptTests {
    @Test("never really tried is an answer, which is what lets this screen gate")
    func theNoneOptionExists() {
        // The triggers screen cannot gate because it has no such option. This
        // one can, and should: waiting for an answer costs nobody a
        // fabrication when "nothing" is on the list.
        #expect(PriorAttempt.allCases.filter(\.isNone).count == 1)
        #expect(PriorAttempt.neverTried.isNone)

        let answers = OnboardingAnswers()
        #expect(answers.hasAnsweredPriorAttempts == false)
        answers.toggle(PriorAttempt.neverTried)
        #expect(answers.hasAnsweredPriorAttempts)
    }

    @Test("choosing something clears never really tried")
    func somethingClearsNothing() {
        let answers = OnboardingAnswers()
        answers.toggle(PriorAttempt.neverTried)
        answers.toggle(PriorAttempt.coldTurkey)
        #expect(answers.priorAttempts == [.coldTurkey])
    }

    @Test("choosing never really tried clears everything else")
    func nothingClearsSomething() {
        let answers = OnboardingAnswers()
        answers.toggle(PriorAttempt.coldTurkey)
        answers.toggle(PriorAttempt.patches)
        answers.toggle(PriorAttempt.neverTried)
        #expect(answers.priorAttempts == [.neverTried])
    }

    @Test("no sequence of taps can hold the exclusive answer beside another")
    func exclusivitySurvivesAnyOrder() {
        // Three taps deep over every option, because the pairwise orders are
        // the ones already thought of.
        for first in PriorAttempt.allCases {
            for second in PriorAttempt.allCases {
                for third in PriorAttempt.allCases {
                    let answers = OnboardingAnswers()
                    [first, second, third].forEach { answers.toggle($0) }
                    let held = answers.priorAttempts
                    #expect(
                        !(held.contains(.neverTried) && held.count > 1),
                        "\(first)/\(second)/\(third) held both"
                    )
                }
            }
        }
    }

    @Test("everything else stays multi-select")
    func realAttemptsCombine() {
        // Most people have a list — that is what the helper says, so the
        // control has to allow one.
        let answers = OnboardingAnswers()
        answers.toggle(PriorAttempt.coldTurkey)
        answers.toggle(PriorAttempt.patches)
        answers.toggle(PriorAttempt.prescription)
        #expect(answers.priorAttempts == [.coldTurkey, .patches, .prescription])
    }

    @Test("prescription medicines are named rather than quietly left off")
    func prescriptionIsListed() {
        // Someone prescribed varenicline has tried something more effective
        // than anything this app offers. Omitting it from the list would be the
        // product editing the user's history to flatter itself.
        #expect(PriorAttempt.prescription.label.contains("varenicline"))
    }

    @Test("nothing tried before moves the plan")
    func priorAttemptsDoNotAffectThePlan() {
        // The helper promises no wrong answers. Scoring these would make that
        // sentence false, and no evidence in the vault supports a rule anyway.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(6, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
        answers.usesWhenIllInBed = true

        let before = TaperPlanner.plan(for: answers.taperInput!)
        PriorAttempt.allCases.forEach { answers.toggle($0) }
        let after = TaperPlanner.plan(for: answers.taperInput!)

        #expect(before.dependence == after.dependence)
        #expect(before.weeklyCapsMg == after.weeklyCapsMg)
        #expect(before.replacement.patchMg == after.replacement.patchMg)
    }
}

/// Covers O9, the one question that changes what the run does next. A skipped
/// screen is invisible from the outside — nothing renders and nothing errors —
/// so the routing is asserted here rather than inferred from driving the app.
struct ReadinessTests {
    @Test("the question starts unanswered rather than defaulted either way")
    func startsNil() {
        // Defaulting to a date addresses someone who has not agreed to one;
        // defaulting to reduction quietly removes the screen that asks.
        #expect(OnboardingAnswers().planShape == nil)
    }

    @Test("choosing a date is what makes the date screen appear")
    func aDateIsAsked() {
        let answers = OnboardingAnswers()
        answers.planShape = .quitDate
        #expect(answers.shouldAsk(.quitDate))
    }

    @Test("saying date later skips the picker rather than showing it to decline")
    func reduceFirstSkipsTheDate() {
        // Asking someone to decline twice reads as the app not having listened.
        let answers = OnboardingAnswers()
        answers.planShape = .reduceFirst
        #expect(answers.shouldAsk(.quitDate) == false)
    }

    @Test("an unanswered fork does not open the date screen by default")
    func unansweredDoesNotAsk() {
        #expect(OnboardingAnswers().shouldAsk(.quitDate) == false)
    }

    @Test("every other step is asked unless it has a reason not to be")
    func nothingElseIsSkippedByAccident() {
        // A skip is a decision. Any step quietly dropped here is a question the
        // user never sees and nobody notices missing.
        let answers = OnboardingAnswers()
        answers.toggle(.pouches)
        answers.planShape = .quitDate
        for step in OnboardingStep.allCases {
            #expect(answers.shouldAsk(step), "\(step) was skipped without a reason")
        }
    }

    @Test("a run with nothing that prints a strength skips that question")
    func strengthStillSkipsForCigarettesOnly() {
        // The pre-existing branch, now assertable rather than buried in the
        // flow's private helper.
        let answers = OnboardingAnswers()
        answers.toggle(.cigarettes)
        #expect(answers.shouldAsk(.strength) == false)
        answers.toggle(.nrt)
        #expect(answers.shouldAsk(.strength))
    }

    @Test("both options describe what the app will actually do")
    func bothOptionsAreRealPlans() {
        // "Both are real plans" is the helper's claim, so neither option may be
        // a placeholder. The conditional phrasing on the second is the framing
        // the one trial aimed at not-yet-ready users scored best on.
        #expect(PlanShape.allCases.count == 2)
        #expect(PlanShape.allCases.allSatisfy { !$0.detail.isEmpty })
        #expect(PlanShape.reduceFirst.detail.contains("if and when you're ready"))
        #expect(PlanShape.quitDate.needsQuitDate)
        #expect(PlanShape.reduceFirst.needsQuitDate == false)
    }

    @Test("reducing without a date is a plan the planner supports")
    func reductionOnlyProducesAPlan() {
        // If a nil date produced no plan, "reduce first" would be an option
        // that leads nowhere — and the screen would be offering a dead end as
        // one of two real choices.
        let plan = TaperPlanner.plan(for: TaperInput(
            startingCapMg: 18,
            minutesToFirstUse: 20,
            usesWhenIllInBed: true,
            weeksUntilQuitDate: nil
        ))
        #expect(plan.weeklyCapsMg == [18])
        #expect(plan.reachesZero == false)
    }
}

/// Covers O10 — the one screen with a clock in it, and the only place the
/// planner's stretch becomes visible to the user.
struct QuitDateTests {
    /// A fixed day, so the suite never has to guess what today is.
    private let today = Date(timeIntervalSince1970: 1_760_000_000)

    private func answers(pouches: Int = 6, minutes: Int = 20, weeksOut: Int? = 8) -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        answers.now = { self.today }
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(pouches, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == minutes }
        answers.usesWhenIllInBed = true
        answers.planShape = .quitDate
        answers.quitDate = weeksOut.map { QuitDate.date(weeksFrom: today, weeks: $0) }
        return answers
    }

    @Test("runway is floored, so the last step never lands after the date")
    func weeksAreFloored() {
        // Ten days is one week of runway, not one and a half. Rounding up would
        // give the plan more weeks than the user has and put the final step
        // past the date they picked.
        // 11 days is the discriminating case: floored it is one week, rounded
        // it is two — and two would put the last step four days past the date.
        let elevenDays = Calendar.current.date(byAdding: .day, value: 11, to: today)!
        #expect(QuitDate.weeks(from: today, to: elevenDays) == 1)
        let twentyDays = Calendar.current.date(byAdding: .day, value: 20, to: today)!
        #expect(QuitDate.weeks(from: today, to: twentyDays) == 2)
        #expect(QuitDate.weeks(from: today, to: QuitDate.date(weeksFrom: today, weeks: 8)) == 8)
    }

    @Test("a date today or in the past still reads as a week, not as zero or less")
    func nearDatesDoNotGoNegative() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        #expect(QuitDate.weeks(from: today, to: today) == 1)
        #expect(QuitDate.weeks(from: today, to: yesterday) == 1)
    }

    @Test("the time of day a date is chosen does not cost a week")
    func comparesCalendarDaysNotElapsedTime() {
        // Picked at 11pm against a date at 9am is still the same number of
        // days apart.
        let lateEvening = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: today)!
        let target = QuitDate.date(weeksFrom: today, weeks: 8)
        #expect(QuitDate.weeks(from: lateEvening, to: target) == 8)
    }

    @Test("a comfortable date reaches zero and says so plainly")
    func roomyDateIsNotStretched() {
        let summary = answers(weeksOut: 8).quitDateSummary
        #expect(summary?.isStretched == false)
        #expect(summary?.runway == "8 weeks out")
        #expect(summary?.caption.contains("step 18 → 0 without any cliff") == true)
    }

    @Test("a date sooner than the steps can go says so rather than pretending")
    func tightDateIsCalledOut() {
        // The board draws only the comfortable case. This is the one that
        // matters: the planner stretches rather than compressing, because a
        // schedule too steep to keep is worse than no schedule — and a stretch
        // the screen does not mention is the app disagreeing with the date in
        // front of the user without saying so.
        let answers = answers(pouches: 10, minutes: 3, weeksOut: 2)
        let summary = answers.quitDateSummary
        #expect(summary?.isStretched == true)
        #expect(summary?.runway == "2 weeks out")
        #expect(summary?.caption.contains("quicker than your steps can safely go") == true)
        // Names the length the plan will actually be, not just that it changed.
        #expect(summary?.caption.contains("7 weeks instead") == true)
    }

    @Test("the stretch the screen reports is the one the planner performed")
    func captionMatchesThePlan() {
        let answers = answers(pouches: 10, minutes: 3, weeksOut: 2)
        let plan = TaperPlanner.plan(for: answers.taperInput!)
        #expect(plan.stretchedFromRequestedWeeks == 2)
        #expect(answers.quitDateSummary?.caption.contains("\(plan.weeklyCapsMg.count - 1) weeks instead") == true)
    }

    @Test("the picker opens on a date the plan can actually reach")
    func defaultIsAchievable() {
        // Opening on a date that triggers a warning would greet the user with a
        // complaint about a choice they have not made.
        let answers = answers(weeksOut: nil)
        answers.quitDate = answers.defaultQuitDate()
        #expect(answers.quitDateSummary?.isStretched == false)
    }

    @Test("one week reads as a week rather than as 1 weeks")
    func singularRunway() {
        #expect(answers(weeksOut: 1).quitDateSummary?.runway == "1 week out")
        #expect(answers(pouches: 10, minutes: 3, weeksOut: 1).quitDateSummary?.caption.hasPrefix("A week is quicker") == true)
    }

    @Test("a date reaches the planner, and moves the schedule it produces")
    func theDateChangesThePlan() {
        // The whole point of the screen. Nothing on it would look wrong if the
        // date never arrived at the planner.
        let dated = answers(weeksOut: 8)
        #expect(dated.taperInput?.weeksUntilQuitDate == 8)
        #expect(TaperPlanner.plan(for: dated.taperInput!).reachesZero)
    }

    @Test("choosing to reduce first keeps a stale date out of the plan")
    func reduceFirstIgnoresAnyDate() {
        // Someone can pick a date, go back, and switch to reducing. The date
        // they abandoned must not still be steering the schedule.
        let answers = answers(weeksOut: 8)
        answers.planShape = .reduceFirst
        #expect(answers.weeksUntilQuitDate == nil)
        #expect(answers.taperInput?.weeksUntilQuitDate == nil)
        #expect(answers.quitDateSummary == nil)
    }
}

/// Covers the picker's lower bound, which is a date comparison masquerading as
/// a day comparison — and therefore wrong in a way only the clock reveals.
struct QuitDateBoundsTests {
    @Test("today stays selectable at every hour of the day")
    func todayIsNeverGreyedOut() {
        // DatePicker compares instants even while showing only days. A bound of
        // "now" makes today unavailable from a minute past midnight onward, and
        // the user just sees today greyed out with nothing explaining why.
        let answers = OnboardingAnswers()
        let day = Date(timeIntervalSince1970: 1_760_000_000)
        for hour in [0, 1, 9, 13, 23] {
            let instant = Calendar.current.date(bySettingHour: hour, minute: 59, second: 0, of: day)!
            answers.now = { instant }
            #expect(answers.earliestQuitDate() <= Calendar.current.startOfDay(for: instant))
        }
    }

    @Test("yesterday stays out of reach")
    func thePastIsStillExcluded() {
        // The bound still has a job: a quit date in the past is not a plan.
        let answers = OnboardingAnswers()
        let day = Date(timeIntervalSince1970: 1_760_000_000)
        answers.now = { day }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        #expect(answers.earliestQuitDate() > yesterday)
    }

    @Test("today is a week of runway, so offering it is not offering nothing")
    func todayIsAMeaningfulAnswer() {
        let day = Date(timeIntervalSince1970: 1_760_000_000)
        #expect(QuitDate.weeks(from: day, to: day) == 1)
    }
}

/// Covers what happens when the clock moves under the screen, and when the
/// user leaves a date behind and comes back to it.
struct QuitDateContinuityTests {
    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func answers(_ clock: @escaping () -> Date) -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        answers.now = clock
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(6, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
        answers.usesWhenIllInBed = true
        answers.planShape = .quitDate
        return answers
    }

    @Test("the plan and the sentence under it use the same runway")
    func oneClockReadPerSummary() {
        // The summary used to read the clock twice — once through the planner's
        // input and once for the caption. A day turning over between the two
        // reads has the planner working from one number while the sentence
        // quotes another, and nothing on screen would look wrong.
        //
        // The clock here jumps a week per read, which is the same defect
        // magnified until it is visible.
        var reads = 0
        let answers = answers {
            defer { reads += 1 }
            return Calendar.current.date(byAdding: .day, value: reads * 7, to: self.day)!
        }
        answers.quitDate = QuitDate.date(weeksFrom: day, weeks: 8)

        // Eight weeks on the first read, seven on a second. The pill has to
        // report the one the plan was actually built from.
        #expect(answers.quitDateSummary?.runway == "8 weeks out")
    }

    @Test("a date the user chose survives a trip back through the run")
    func aDeliberateChoiceIsKept() {
        // Going back to change an earlier answer should not silently discard a
        // later one.
        let answers = answers { self.day }
        let chosen = QuitDate.date(weeksFrom: day, weeks: 9)
        answers.quitDate = chosen
        answers.settleQuitDate()
        #expect(answers.quitDate == chosen)
    }

    @Test("a date that has gone stale is replaced rather than shown")
    func aPastDateIsReplaced() {
        // A date picked before a detour through the rest of the run can be in
        // the past by the time they come back, and the picker cannot even
        // display it — the row would show a date the control refuses to select.
        let answers = answers { self.day }
        answers.quitDate = Calendar.current.date(byAdding: .day, value: -3, to: day)!
        answers.settleQuitDate()
        #expect(answers.quitDate == answers.defaultQuitDate())
        #expect(answers.quitDateSummary?.isStretched == false)
    }

    @Test("an unset date settles on the default")
    func anEmptyDateGetsTheDefault() {
        let answers = answers { self.day }
        answers.settleQuitDate()
        #expect(answers.quitDate == answers.defaultQuitDate())
    }
}

/// Covers O11 — the plan said back before the user commits to it.
///
/// The board draws one run. Most of this suite is the three it does not: a run
/// with no date, a run whose date the descent cannot reach, and an intake that
/// reads as a typo.
struct PlanPreviewTests {
    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func answers(
        pouches: Int = 6,
        minutes: Int = 20,
        weeksOut: Int? = 8,
        clock: (() -> Date)? = nil
    ) -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        answers.now = clock ?? { self.day }
        answers.toggle(.pouches)
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
        answers.setAmount(pouches, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == minutes }
        answers.usesWhenIllInBed = true
        answers.planShape = weeksOut == nil ? .reduceFirst : .quitDate
        answers.quitDate = weeksOut.map { QuitDate.date(weeksFrom: day, weeks: $0) }
        return answers
    }

    @Test("a dated run gets this week's cap, a countdown, and three stops")
    func theBoardsRun() {
        let preview = answers().planPreview
        #expect(preview?.capMg == 18)
        #expect(preview?.countdownDays == 56)
        #expect(preview?.quitDate == QuitDate.date(weeksFrom: day, weeks: 8))
        #expect(preview?.milestones.count == 3)
        #expect(preview?.milestones.first?.title == "Hold at 18 mg — this week")
        #expect(preview?.milestones.last?.title.contains("your quit date") == true)
    }

    @Test("the countdown comes off the plan, not off the date the user asked for")
    func stretchedRunCountsThePlan() {
        // The case the board does not draw. A date sooner than the descent can
        // reach is stretched by the planner, and a countdown taken from the
        // user's date would then run out with two weeks of schedule still to
        // go — the app disagreeing with itself on the last screen before it
        // asks for commitment.
        let answers = answers(pouches: 10, minutes: 3, weeksOut: 2)
        let plan = TaperPlanner.plan(for: answers.taperInput!)
        #expect(plan.stretchedFromRequestedWeeks == 2)

        let preview = answers.planPreview
        #expect(preview?.countdownDays == 49)
        #expect(preview?.countdownDays != 14)
        #expect(preview?.quitDate == QuitDate.date(weeksFrom: day, weeks: 7))
    }

    @Test("a run with no date gets no countdown and invents no rate")
    func undatedRunHoldsWhereItIs() {
        // The planner holds one cap for this user deliberately, because most
        // nicotine users are not ready to name a date. A borrowed countdown
        // here would put them back in the product they declined.
        let preview = answers(weeksOut: nil).planPreview
        #expect(preview?.countdownDays == nil)
        #expect(preview?.quitDate == nil)
        #expect(preview?.milestones.count == 2)
        #expect(preview?.milestones.contains { $0.title.contains("quit date") } == false)
        // No weekly step figure anywhere, because the model produced none.
        #expect(preview?.milestones.contains { $0.title.contains("mg a week") } == false)
        #expect(preview?.note.contains("if and when") == true)
    }

    @Test("the step named is the drop the plan actually makes next week")
    func stepMatchesTheDescent() {
        let answers = answers()
        let plan = TaperPlanner.plan(for: answers.taperInput!)
        let step = plan.weeklyCapsMg[0] - plan.weeklyCapsMg[1]
        #expect(step == 2)
        #expect(answers.planPreview?.milestones[1].title == "Step down about 2 mg a week")
        #expect(answers.planPreview?.milestones[1].detail.hasPrefix("8 steps") == true)
    }

    @Test("a stretched run's step is its own, not the comfortable run's")
    func stepFollowsTheStretchedSchedule() {
        // 30 mg over the seven weeks the planner insisted on, not the two asked
        // for — a step sized to the requested date would be the one number on
        // screen the plan does not honour.
        #expect(answers(pouches: 10, minutes: 3, weeksOut: 2).planPreview?
            .milestones[1].title == "Step down about 4.5 mg a week")
    }

    @Test("the landing names the form the user chose and the planner's strength")
    func landingFollowsTheTreatmentAnswer() {
        let answers = answers()
        answers.toggle(.patch)
        answers.toggle(.lozenge)
        let plan = TaperPlanner.plan(for: answers.taperInput!)
        #expect(plan.replacement.fastActingMg == 2)
        #expect(answers.planPreview?.milestones.last?.detail.contains("2 mg lozenge") == true)
    }

    @Test("someone on gum is not told about a lozenge")
    func landingUsesTheirOwnForm() {
        let answers = answers()
        answers.toggle(.gum)
        #expect(answers.planPreview?.milestones.last?.detail.contains("2 mg gum") == true)
        #expect(answers.planPreview?.milestones.last?.detail.contains("lozenge") == false)
    }

    @Test("the patch alone and no treatment at all each get their own ending")
    func everyTreatmentAnswerHasABranch() {
        // Three answers reach this screen and all three happen. Declining a
        // treatment is a real answer, and describing a lozenge to someone who
        // said no to one is the screen not having listened.
        let patchOnly = answers()
        patchOnly.toggle(.patch)
        #expect(patchOnly.planPreview?.milestones.last?.detail.contains("patch is the last") == true)

        let none = answers()
        none.deferTreatment()
        #expect(none.planPreview?.milestones.last?.detail.contains("Nothing to come off") == true)
        #expect(none.planPreview?.milestones.last?.detail.contains("mg") == false)
    }

    @Test("an intake that reads as a typo is questioned before tracking starts")
    func implausibleIntakeIsFlagged() {
        // The planner has carried this flag since it was written and no screen
        // has ever shown it. A cap set from a mistyped strength does not fail
        // loudly — it never binds, so the app agrees with everything the user
        // logs and the taper quietly does nothing.
        let answers = answers()
        // Pouches off, cigarettes on: 70 a day at 1.5 mg is 105, which is the
        // shape of a mistyped count rather than a habit.
        answers.toggle(.pouches)
        answers.toggle(.cigarettes)
        answers.setAmount(70, for: .cigarettes)
        #expect(TaperPlanner.plan(for: answers.taperInput!).intakeLooksImplausible)
        #expect(answers.planPreview?.caution?.contains("105 mg a day") == true)
    }

    @Test("an ordinary intake carries no warning")
    func plausibleIntakeIsNotFlagged() {
        #expect(answers().planPreview?.caution == nil)
    }

    @Test("the countdown and the date beneath it come from one reading of the clock")
    func oneClockReadPerPreview() {
        // Two reads can straddle midnight, and the plan then covers a runway
        // that ends a day away from the date printed beside it. The clock here
        // jumps a week per read, which is the same defect magnified until an
        // assertion can see it.
        var reads = 0
        let start = day
        let answers = answers(clock: {
            defer { reads += 1 }
            return Calendar.current.date(byAdding: .day, value: reads * 7, to: start)!
        })
        #expect(answers.planPreview?.countdownDays == 56)
        #expect(answers.planPreview?.quitDate == QuitDate.date(weeksFrom: day, weeks: 8))
    }

    @Test("a half-answered run has no plan to preview")
    func incompleteRunPreviewsNothing() {
        let answers = answers()
        answers.usesWhenIllInBed = nil
        #expect(answers.planPreview == nil)
    }
}
