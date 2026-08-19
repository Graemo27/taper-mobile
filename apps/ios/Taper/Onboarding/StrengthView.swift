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
    private static let exactEntryID = "exact-strength"

    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "What you use",
            progress: OnboardingStep.strength.progress,
            question: "What strength, per piece?",
            helper: "The mg number on the Drug Facts panel. Not sure is fine — we'll assume \(Int(StrengthOption.assumedWhenUnsure(for: answers.sources))) mg and you can correct it later.",
            cta: "Continue",
            onContinue: canContinue ? onContinue : nil,
            onBack: onBack
        ) {
            ScrollViewReader { proxy in
                VStack(spacing: AppSpacing.smPlus) {
                ForEach(StrengthOption.options(for: answers.sources)) { option in
                    OptionCard(
                        label: option.label,
                        isSelected: answers.strength == option
                    ) {
                        answers.strength = option
                    }
                }

                    if answers.strength?.isAtLeast == true {
                        exactEntry.id(Self.exactEntryID)
                    }
                }
                .padding(.horizontal, AppLayout.gutter)
                // The entry appears below the fold, so revealing it without
                // moving to it looks like the tap did nothing.
                .onChange(of: answers.strength) { _, new in
                    guard new?.isAtLeast == true else { return }
                    withAnimation { proxy.scrollTo(Self.exactEntryID, anchor: .bottom) }
                }
            }
        }
    }

    /// An open-ended answer is a floor, not a value, so it asks for the number.
    /// Planning on the floor would size the cap for 8 mg when the pouch might
    /// be 12 — a cap set below what someone actually uses is one they blow on
    /// day one, and that is worse than not being given one.
    private var exactEntry: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("How many mg, exactly?")
                .font(AppFont.text(AppSize.label, .medium))
                .foregroundStyle(AppColor.ink)

            HStack(spacing: AppSpacing.m) {
                stepButton("minus") { adjust(-1) }

                Text(answers.exactStrengthMg.map { "\(Int($0)) mg" } ?? "— mg")
                    .font(AppFont.display(AppSize.unit))
                    .foregroundStyle(answers.exactStrengthMg == nil ? AppColor.inkFaint : AppColor.ink)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(answers.exactStrengthMg.map { "\(Int($0)) milligrams" } ?? "Not set")

                stepButton("plus") { adjust(1) }
            }
            .padding(AppSpacing.l)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .strokeBorder(AppColor.line, lineWidth: 1)
            }
        }
        .padding(.top, AppSpacing.xs)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.ink)
                .frame(width: AppLayout.tap, height: AppLayout.tap)
                .background(AppColor.sunken, in: Circle())
        }
        .accessibilityLabel(symbol == "plus" ? "More" : "Less")
    }

    private func adjust(_ delta: Double) {
        let floor = answers.strength?.mg ?? StrengthOption.assumedWhenUnsure(for: answers.sources)
        let current = answers.exactStrengthMg ?? floor
        // Never below the floor the user already chose — they said "or more".
        answers.exactStrengthMg = max(floor, min(current + delta, 60))
    }

    private var canContinue: Bool {
        answers.strength != nil && !answers.needsExactStrength
    }
}

#Preview {
    StrengthView(answers: OnboardingAnswers(), onContinue: {}, onBack: {})
}
