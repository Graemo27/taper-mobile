import SwiftUI

/// O2 — how strong one of whatever they use is.
///
/// Single-select, unlike O1: a pouch has one strength, and offering several
/// would produce a number nobody could act on. The list ends at "8 mg or more"
/// rather than climbing, because commercial pouches run past 40 mg and a
/// picker that reached them would read as a menu.
///
/// "Not sure" is a first-class answer, not an escape hatch. The number lives on
/// the tin and most people are not holding one while answering — refusing to
/// continue until they fetch it is how a run gets abandoned. It resolves to the
/// middle of the range, and the helper text says so, so the screen and the
/// arithmetic cannot disagree.
struct StrengthView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "What you use",
            progress: OnboardingStep.strength.progress,
            question: "What strength, per piece?",
            helper: "The mg number on the Drug Facts panel. Not sure is fine — we'll assume \(Int(StrengthOption.assumedWhenUnsure)) mg and you can correct it later.",
            cta: "Continue",
            onContinue: answers.strength == nil ? nil : onContinue,
            onBack: onBack
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(StrengthOption.pouch) { option in
                    OptionCard(
                        label: option.label,
                        isSelected: answers.strength == option
                    ) {
                        answers.strength = option
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }
}

#Preview {
    StrengthView(answers: OnboardingAnswers(), onContinue: {}, onBack: {})
}
