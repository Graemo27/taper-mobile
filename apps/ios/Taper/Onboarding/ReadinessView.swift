import SwiftUI

/// O9 — a date, or not yet.
///
/// The only question in the run that changes what the run does next: choosing
/// to reduce first skips the quit-date screen rather than showing it and
/// letting the user decline.
///
/// Both options are presented as plans, without a recommended one. That is a
/// deliberate refusal to nudge: a date is better supported by the evidence, and
/// someone who will not set one today is better served reducing than closing
/// the app. Pushing here would trade the second user for nothing.
struct ReadinessView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Your plan",
            progress: OnboardingStep.readiness.progress,
            question: "Want to pick a quit date?",
            helper: "Both are real plans — and the door stays open either way.",
            cta: "Continue",
            onContinue: answers.planShape == nil ? nil : onContinue,
            onBack: onBack
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(PlanShape.allCases) { shape in
                    OptionCard(
                        label: shape.label,
                        detail: shape.detail,
                        isSelected: answers.planShape == shape
                    ) {
                        answers.planShape = shape
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }
}

#Preview {
    ReadinessView(answers: OnboardingAnswers(), onContinue: {}, onBack: {})
}
