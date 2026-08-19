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
