import SwiftUI

/// O11 — the plan, drawn.
///
/// The last screen in the run and the first one that shows the user something
/// rather than asking. Every figure on it comes from `PlanPreview`, which is
/// where the branching lives: a run with no quit date has no countdown badge
/// and one fewer stop, and an intake that reads as a typo gets a warning the
/// board never drew. None of that is decided here — a screen that chose its own
/// wording for those cases would be a second place the plan is described.
struct PlanPreviewView: View {
    let preview: PlanPreview
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Your plan",
            progress: OnboardingStep.planPreview.progress,
            question: "Here's your plan.",
            // The board names the plan tab, which does not exist. Dropping the
            // destination but keeping "changes later" was the worse half of
            // that fix: the promise survived and only its falsifiable part
            // went. Today the CTA is one-way, so the actionable half of this
            // sentence has to be one the build can honour — going back. The
            // reassurance the board wanted is the other half, and it stays
            // true either way: a plan is not a commitment.
            helper: "Built from what you told us. Nothing here is a commitment — go back and change any answer before you start.",
            cta: "Start tracking",
            onContinue: onContinue,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                capTile
                if let caution = preview.caution { cautionNote(caution) }
                timeline
                note
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }

    /// This week's ceiling, and how long the descent runs.
    ///
    /// The only screen element that fills with the accent, because the cap is
    /// the one number the user acts on tomorrow morning.
    private var capTile: some View {
        HStack(alignment: .center, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("This week's cap")
                    .font(AppFont.text(AppSize.caption, .medium))
                    .foregroundStyle(AppColor.onAccent)

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Text(preview.capMg.clean)
                        .font(AppFont.display(AppSize.metric))
                    Text("mg a day")
                        .font(AppFont.display(AppSize.unitSmall))
                }
                .foregroundStyle(AppColor.onAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Absent for a run holding where it is. The badge counts the plan's
            // own length, so a stretched date shows the schedule that will
            // actually happen rather than the one that was asked for.
            if let days = preview.countdownDays {
                VStack(spacing: 0) {
                    Text("\(days)")
                        .font(AppFont.display(AppSize.title))
                    Text("days")
                        .font(AppFont.text(AppSize.nano, .medium))
                }
                .foregroundStyle(AppColor.ink)
                .frame(width: 76, height: 76)
                .background(AppColor.veilOnAccent, in: Circle())
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.l)
        .background(AppColor.accent, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
        .accessibilityElement(children: .combine)
    }

    /// The stops, in order, on a rail.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(preview.milestones.enumerated()), id: \.element.id) { index, milestone in
                HStack(alignment: .top, spacing: AppSpacing.mPlus) {
                    rail(at: index)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(milestone.title)
                            .font(AppFont.text(AppSize.body, .semibold))
                            .foregroundStyle(AppColor.ink)
                        Text(milestone.detail)
                            .font(AppFont.text(AppSize.caption))
                            .lineSpacing(AppLeading.tight - AppSize.caption)
                            .foregroundStyle(AppColor.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, isLast(index) ? AppSpacing.xs : AppSpacing.l)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(AppSpacing.l)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
    }

    /// The dot and the line beside one stop.
    ///
    /// Only the first is filled. The others are stops the user has not reached,
    /// and drawing them as reached would be the screen congratulating someone
    /// for a descent they have not started.
    private func rail(at index: Int) -> some View {
        let isNow = index == 0
        return VStack(spacing: 0) {
            // The stub above a dot continues the segment arriving at it, so
            // only the one leaving the current stop is tinted. Tinting them all
            // would draw the whole descent as live.
            Rectangle()
                .fill(incoming(at: index))
                .frame(width: 2, height: 4)

            Circle()
                .fill(isNow ? AppColor.accent : AppColor.surface)
                .overlay {
                    Circle().strokeBorder(
                        isNow ? AppColor.accentEdge : AppColor.lineStrong,
                        lineWidth: 1.5
                    )
                }
                .frame(width: 12, height: 12)

            if !isLast(index) {
                Rectangle()
                    .fill(isNow ? AppColor.accentTint : AppColor.sunken)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: AppSpacing.mPlus)
        .accessibilityHidden(true)
    }

    /// The reassurance under the timeline — what happens on a bad week.
    private var note: some View {
        Text(preview.note)
            .font(AppFont.text(AppSize.micro))
            .lineSpacing(AppLeading.snug - AppSize.micro)
            .foregroundStyle(AppColor.onAccentTint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.smPlus)
            .background(AppColor.accentTint, in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    /// The warning for an intake that reads as a mis-entry.
    ///
    /// Directly under the cap it questions, and set a size up from the note: it
    /// is the one thing on this screen the user may need to act on before
    /// tapping Start.
    private func cautionNote(_ text: String) -> some View {
        Text(text)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.cautionInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.m)
            .background(AppColor.cautionSurface, in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    private func incoming(at index: Int) -> Color {
        if index == 0 { return .clear }
        return index == 1 ? AppColor.accentTint : AppColor.sunken
    }

    private func isLast(_ index: Int) -> Bool { index == preview.milestones.count - 1 }
}

#Preview {
    let answers = OnboardingAnswers()
    answers.toggle(.pouches)
    answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
    answers.setAmount(6, for: .pouches)
    answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
    answers.usesWhenIllInBed = true
    answers.planShape = .quitDate
    answers.quitDate = QuitDate.date(weeksFrom: Date(), weeks: 8)
    answers.toggle(.patch)
    answers.toggle(.lozenge)
    return PlanPreviewView(preview: answers.planPreview!, onContinue: {}, onBack: {})
}
