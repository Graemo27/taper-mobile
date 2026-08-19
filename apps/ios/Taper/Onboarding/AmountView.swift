import SwiftUI

/// O3 — how much of each source, one row per thing the user named.
///
/// Every row counts in its own unit: pouches a day, puffs a day, packs a day.
/// The screen deliberately shows no running total. A summed milligram figure
/// would be assembled from two measurement bases and two unsourced estimates,
/// and presenting that as a headline number would give it a precision it does
/// not have — see Q12 in the vault.
struct AmountView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "What you use",
            progress: OnboardingStep.amount.progress,
            question: "How much do you use?",
            helper: "Your average, not your best day. Rough is fine — we only need a starting line.",
            cta: "Continue",
            onContinue: answers.orderedSources.isEmpty ? nil : onContinue,
            onBack: onBack
        ) {
            VStack(spacing: AppSpacing.smPlus) {
                ForEach(answers.orderedSources) { source in
                    AmountRow(
                        title: source.label,
                        subtitle: subtitle(for: source),
                        amount: answers.amount(for: source),
                        step: source.step
                    ) { newValue in
                        answers.setAmount(newValue, for: source)
                    }
                }
            }
            .padding(.horizontal, AppLayout.gutter)
        }
    }

    /// Names the unit, and the strength only where the user gave one. A source
    /// with an estimated dose says nothing about milligrams, because showing an
    /// estimate here would read as something they had told us.
    private func subtitle(for source: NicotineSource) -> String {
        guard source.usesPerUnitStrength, let mg = answers.strengthMgPerUnit else {
            return source.unitLabel
        }
        return "\(source.unitLabel) · \(mg.clean) mg each"
    }
}

/// One counted source: what it is, what unit it is in, and a stepper.
struct AmountRow: View {
    let title: String
    let subtitle: String
    let amount: Int
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
                Text(subtitle)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppSpacing.s) {
                stepButton("minus", filled: false) { onChange(amount - step) }
                    .disabled(amount == 0)
                    .opacity(amount == 0 ? 0.35 : 1)

                Text("\(amount)")
                    .font(AppFont.display(AppSize.metric))
                    .foregroundStyle(AppColor.ink)
                    // Wide enough for three digits, so the stepper does not
                    // shuffle sideways as the count crosses 10 or 100.
                    .frame(minWidth: 56)
                    .lineLimit(1)

                stepButton("plus", filled: true) { onChange(amount + step) }
            }
            .fixedSize()
        }
        .padding(.vertical, AppSpacing.mPlus)
        .padding(.leading, AppSpacing.xl)
        .padding(.trailing, AppSpacing.mPlus)
        .frame(minHeight: 76)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .strokeBorder(AppColor.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue("\(amount)")
    }

    private func stepButton(_ symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(filled ? AppColor.onAccent : AppColor.ink)
                .frame(width: AppLayout.tap, height: AppLayout.tap)
                .background {
                    if filled {
                        Circle().fill(AppColor.accent)
                    } else {
                        Circle().strokeBorder(AppColor.lineStrong, lineWidth: 1)
                    }
                }
        }
        .accessibilityLabel(filled ? "More" : "Less")
    }
}

extension Double {
    /// Drops a trailing `.0`, so 3 reads as "3 mg" and 1.5 as "1.5 mg".
    var clean: String {
        self == rounded() ? String(Int(self)) : String(self)
    }
}
