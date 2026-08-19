import SwiftUI

/// O5 — whether the habit survives being ill in bed.
///
/// The second of the two dependence items the planner reads, and the one that
/// sounds like small talk. It is not: using through a cold, when the thing is
/// actively unpleasant, is the clearest evidence that the habit is running on
/// withdrawal rather than on wanting it. The helper says so, because a question
/// whose purpose is invisible gets a careless answer.
///
/// Both answers are answers. There is no skip, and the CTA stays inert until
/// one is tapped, because "no" and "unanswered" reach the planner as different
/// things — see `OnboardingAnswers.usesWhenIllInBed`.
struct SickInBedView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Your habit",
            progress: OnboardingStep.sickInBed.progress,
            question: "Do you still use when you're sick in bed?",
            helper: "A cold, the flu. It's one of the strongest signs of how deep the habit runs.",
            cta: "Continue",
            onContinue: answers.hasAnsweredSickInBed ? onContinue : nil,
            onBack: onBack
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(SickInBedOption.all) { option in
                    OptionCard(
                        label: option.label,
                        isSelected: answers.usesWhenIllInBed == option.stillUses
                    ) {
                        answers.usesWhenIllInBed = option.stillUses
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }
}

#Preview {
    SickInBedView(answers: OnboardingAnswers(), onContinue: {}, onBack: {})
}
