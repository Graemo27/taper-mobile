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
