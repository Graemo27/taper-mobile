import SwiftUI

/// O10 — the quit date.
///
/// The screen's job is not to collect a date but to say what that date means.
/// The case worth building carefully is the one the board does not draw: a date
/// sooner than the descent can safely reach, where the plan stretches past it.
/// Letting that happen silently would leave the app disagreeing with the date
/// on screen without ever saying so.
struct QuitDateView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var isPickingDate = false

    var body: some View {
        OnboardingScaffold(
            section: "Your plan",
            progress: OnboardingStep.quitDate.progress,
            question: "Pick your quit date.",
            helper: "Give the taper at least two weeks of runway — you'll step down on the way there, not overnight.",
            cta: "Continue",
            onContinue: answers.quitDate == nil ? nil : onContinue,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                dateRow
                if let summary = answers.quitDateSummary {
                    Text(summary.caption)
                        .font(AppFont.text(AppSize.caption))
                        .lineSpacing(AppLeading.snug - AppSize.caption)
                        .foregroundStyle(summary.isStretched ? AppColor.cautionInk : AppColor.inkMuted)
                }
            }
            .padding(.horizontal, AppLayout.gutter)
            // The picker opens on a date the plan can actually reach, so nobody
            // starts on a warning about a choice they have not made.
            .onAppear { if answers.quitDate == nil { answers.quitDate = answers.defaultQuitDate() } }
        }
    }

    /// A row that reads as a sentence, not as a form control.
    ///
    /// The system's compact picker brings its own typeface and a grey chip with
    /// it, which puts a second visual language on a screen the board sets in
    /// the display face. Tapping opens the real picker in a sheet.
    private var dateRow: some View {
        Button { isPickingDate = true } label: {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: "calendar")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColor.ink)

                Text(chosenDate.formatted(.dateTime.month(.wide).day()))
                    .font(AppFont.display(AppSize.unit))
                    .foregroundStyle(AppColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let summary = answers.quitDateSummary {
                    Text(summary.runway)
                        .font(AppFont.text(AppSize.nano, .medium))
                        .foregroundStyle(summary.isStretched ? AppColor.cautionInk : AppColor.onAccentTint)
                        .padding(.horizontal, AppSpacing.smPlus)
                        .padding(.vertical, AppSpacing.xs)
                        .background(
                            summary.isStretched ? AppColor.cautionTint : AppColor.accentTint,
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, AppSpacing.lPlus)
            .padding(.vertical, AppSpacing.l)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .strokeBorder(AppColor.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quit date, \(chosenDate.formatted(.dateTime.month(.wide).day()))")
        .sheet(isPresented: $isPickingDate) {
            DatePicker(
                "Quit date",
                selection: Binding(get: { chosenDate }, set: { answers.quitDate = $0 }),
                // No date before today. A quit date in the past is not a plan.
                in: answers.now()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(AppColor.accentEdge)
            .padding(AppLayout.gutter)
            .presentationDetents([.medium])
        }
    }

    private var chosenDate: Date { answers.quitDate ?? answers.defaultQuitDate() }
}

#Preview {
    let answers = OnboardingAnswers()
    answers.toggle(.pouches)
    answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
    answers.setAmount(6, for: .pouches)
    answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
    answers.usesWhenIllInBed = true
    answers.planShape = .quitDate
    return QuitDateView(answers: answers, onContinue: {}, onBack: {})
}
