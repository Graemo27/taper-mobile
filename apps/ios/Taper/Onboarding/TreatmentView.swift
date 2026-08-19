import SwiftUI

/// O5a — what to taper with.
///
/// The turn in the run: every screen before this one asks, and this one
/// recommends. The suggestion is shown as a suggestion — headed, tinted, and
/// sitting above choices the user can ignore — rather than as a preselection
/// they have to notice and undo.
///
/// Every figure on screen comes from `TreatmentSuggestion`, which reads them
/// off the plan. Nothing here is allowed a number of its own.
struct TreatmentView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    private var suggestion: TreatmentSuggestion? { answers.treatmentSuggestion }

    var body: some View {
        OnboardingScaffold(
            section: "Your treatment",
            progress: OnboardingStep.treatment.progress,
            question: "What will you taper with?",
            helper: "Licensed to help people quit — that's what makes these different from what you use now.",
            cta: "Continue",
            onContinue: answers.hasAnsweredTreatment ? onContinue : nil,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.smPlus) {
                if let suggestion {
                    suggestionCard(suggestion)
                }

                ForEach(TreatmentForm.allCases) { form in
                    OptionCard(
                        label: form.label,
                        detail: suggestion?.detail(for: form) ?? form.role,
                        isSelected: answers.treatments.contains(form)
                    ) {
                        answers.toggle(form)
                    }
                }

                OptionCard(
                    label: "Not right now",
                    detail: "You can add one whenever",
                    isSelected: answers.defersTreatment
                ) {
                    answers.deferTreatment()
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }

    /// Named as a suggestion, and separated from the rows below it.
    ///
    /// The alternative — arriving with the recommended forms already ticked —
    /// makes a recommendation look like a decision already taken, and the user
    /// has to spot it before they can disagree with it.
    private func suggestionCard(_ suggestion: TreatmentSuggestion) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("SUGGESTED FOR YOU")
                .font(AppFont.text(AppSize.nano, .medium))
                .tracking(AppTracking.eyebrowWide(AppSize.nano))
                .foregroundStyle(AppColor.onAccentTint)

            Text(suggestion.headline)
                .font(AppFont.display(AppSize.heading))
                .foregroundStyle(AppColor.ink)

            // The user's own answers first, then the one claim — in that order,
            // so the suggestion reads as a consequence of what they said rather
            // than as a house preference with a statistic attached.
            Text(suggestion.blurb)
                .font(AppFont.text(AppSize.caption))
                .lineSpacing(AppLeading.snug - AppSize.caption)
                .foregroundStyle(AppColor.onAccentTint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lPlus)
        .background(AppColor.accentTint, in: RoundedRectangle(cornerRadius: AppRadius.large))
    }
}

#Preview {
    let answers = OnboardingAnswers()
    answers.toggle(.pouches)
    answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
    answers.setAmount(10, for: .pouches)
    answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
    answers.usesWhenIllInBed = true
    return TreatmentView(answers: answers, onContinue: {}, onBack: {})
}
