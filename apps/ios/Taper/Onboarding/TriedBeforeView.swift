import SwiftUI

/// O8 — what they have already tried.
///
/// Gated, unlike the triggers screen before it, and for one reason: "never
/// really tried" is on the list. A user with nothing to report has a true
/// answer to give, so waiting for one costs nobody a fabrication.
///
/// The helper says there are no wrong answers, and the app has to mean it —
/// nothing here reaches the planner. A run that scored people on this would be
/// contradicting the sentence that got them to answer honestly.
struct TriedBeforeView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Your habit",
            progress: OnboardingStep.triedBefore.progress,
            question: "What have you tried before?",
            helper: "Select all that apply. No wrong answers — most people have a list.",
            cta: "Continue",
            onContinue: answers.hasAnsweredPriorAttempts ? onContinue : nil,
            onBack: onBack
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(PriorAttempt.allCases) { attempt in
                    OptionCard(
                        label: attempt.label,
                        isSelected: answers.priorAttempts.contains(attempt)
                    ) {
                        answers.toggle(attempt)
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }
}

#Preview {
    TriedBeforeView(answers: OnboardingAnswers(), onContinue: {}, onBack: {})
}
