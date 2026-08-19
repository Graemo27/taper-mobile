import SwiftUI

/// O1 — what the user is quitting. The first question of the run.
///
/// Multi-select, because dual use is common and a single choice would quietly
/// undercount someone who vapes and uses pouches — the starting cap is summed
/// across everything named here, so a missed source is a cap set too low.
///
/// The helper line does real work: it tells the user that gum, lozenges and
/// patches are coming as *tools*, so they do not list their treatment here and
/// have it counted as something to quit.
struct WhatYouUseView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "What you use",
            progress: OnboardingStep.whatYouUse.progress,
            question: "What are you quitting?",
            helper: "Pick everything you use. Gum, lozenges and patches come next — those are the tools, not the habit.",
            cta: "Continue",
            onContinue: answers.hasChosenSources ? onContinue : nil,
            onBack: nil
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(NicotineSource.allCases) { source in
                    OptionCard(
                        label: source.label,
                        isSelected: answers.sources.contains(source)
                    ) {
                        answers.toggle(source)
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }
}

#Preview {
    WhatYouUseView(answers: OnboardingAnswers()) {}
}
