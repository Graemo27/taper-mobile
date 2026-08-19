import SwiftUI

/// O7 — the moments someone reaches for one.
///
/// The only question in the run with no gate on Continue. Nothing downstream
/// requires a trigger, and someone whose moments are not on the list would
/// otherwise have to tick a false one to get past the screen.
///
/// The helper makes a promise — that the app will meet them here on hard days
/// — which the craving screen is what keeps. Until that screen exists this
/// answer is stored and unread, which is a debt worth naming rather than a
/// reason to soften the copy.
struct TriggersView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Your habit",
            progress: OnboardingStep.triggers.progress,
            question: "When do you reach for one most?",
            helper: "Select all that apply — on hard days, the app will meet you here.",
            cta: "Continue",
            onContinue: onContinue,
            onBack: onBack
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(Trigger.allCases) { trigger in
                    OptionCard(
                        label: trigger.label,
                        isSelected: answers.triggers.contains(trigger)
                    ) {
                        answers.toggle(trigger)
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }
}

#Preview {
    TriggersView(answers: OnboardingAnswers(), onContinue: {}, onBack: {})
}
