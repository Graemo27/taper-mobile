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
