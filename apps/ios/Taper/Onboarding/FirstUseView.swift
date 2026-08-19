import SwiftUI

/// O4 — how soon after waking the first one happens.
///
/// The strongest single dependence item, and the one that decides whether the
/// plan descends slowly or quickly. The helper says so plainly: the answer
/// sizes the steps, and it is not a judgement. That framing is deliberate —
/// under-reporting here produces a schedule too aggressive to keep, and failing
/// a schedule was associated with worse outcomes than never being given one.
struct FirstUseView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Your habit",
            progress: OnboardingStep.firstUse.progress,
            question: "How soon after waking is your first one?",
            helper: "Be honest — this sizes your steps. It isn't a judgement.",
            cta: "Continue",
            onContinue: answers.firstUse == nil ? nil : onContinue,
            onBack: onBack
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(FirstUseOption.all) { option in
                    OptionCard(label: option.label, isSelected: answers.firstUse == option) {
                        answers.firstUse = option
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }
}

#Preview {
    FirstUseView(answers: OnboardingAnswers(), onContinue: {}, onBack: {})
}
