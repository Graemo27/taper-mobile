import SwiftUI

/// O2 — the printed strength, asked once per product that prints one.
///
/// A run naming both pouches and gum has two strengths to give, and they are
/// not interchangeable: gum comes in 2 and 4 mg, pouches in 2 to 8. Answering
/// once for both would apply a pouch figure to gum, which is the same
/// fabrication this screen exists to avoid — just one level further in.
///
/// Sources without a printed figure never reach here; the flow skips the step.
struct StrengthView: View {
    @Bindable var answers: OnboardingAnswers
    let onContinue: () -> Void
    let onBack: () -> Void

    private var sources: [NicotineSource] { answers.sourcesWithPrintedStrength }

    var body: some View {
        OnboardingScaffold(
            section: "What you use",
            progress: OnboardingStep.strength.progress,
            question: sources.count > 1 ? "What strengths?" : "What strength, per piece?",
            helper: helper,
            cta: "Continue",
            onContinue: canContinue ? onContinue : nil,
            onBack: onBack
        ) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    ForEach(sources) { source in
                        section(for: source, proxy: proxy)
                    }
                }
                .padding(.horizontal, AppLayout.gutter)
            }
        }
    }

    /// Names the assumption, and which product it belongs to when there is more
    /// than one. `clean` rather than `Int` because a fractional assumption — a
    /// 1.5 mg lozenge — would otherwise read as "1 mg" here while the planner
    /// used 1.5, which is precisely the disagreement `assumedWhenUnsure(for:)`
    /// promises cannot happen.
    private var helper: String {
        let assumed: String
        if sources.count > 1 {
            assumed = sources
                .map { "\(StrengthOption.assumedWhenUnsure(for: $0).clean) mg for \(shortName($0))" }
                .joined(separator: " and ")
        } else {
            assumed = sources.first.map { "\(StrengthOption.assumedWhenUnsure(for: $0).clean) mg" } ?? ""
        }
        return "The mg number on the pack. Not sure is fine — we'll assume \(assumed) and you can correct it later."
    }

    /// A form that reads inside a sentence. Only pouches and NRT reach this
    /// screen, so the other cases would be dead prose.
    private func shortName(_ source: NicotineSource) -> String {
        source == .pouches ? "pouches" : "gum or lozenges"
    }

    @ViewBuilder
    private func section(for source: NicotineSource, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.smPlus) {
            // Only labelled when there is more than one, so the common
            // single-source run keeps the plain list the design asks for.
            if sources.count > 1 {
                Text(source.label)
                    .font(AppFont.text(AppSize.label, .medium))
                    .foregroundStyle(AppColor.inkMuted)
            }

            ForEach(StrengthOption.options(for: source)) { option in
                OptionCard(label: option.label, isSelected: answers.strengths[source] == option) {
                    answers.strengths[source] = option
                }
            }

            if answers.strengths[source]?.isAtLeast == true {
                exactEntry(for: source).id(source.id)
            }
        }
        .onChange(of: answers.strengths[source]) { _, new in
            // The entry appears below the fold, so revealing it without moving
            // to it looks like the tap did nothing.
            guard new?.isAtLeast == true else { return }
            withAnimation { proxy.scrollTo(source.id, anchor: .bottom) }
        }
    }

    /// An open-ended answer is a floor, not a value. Planning on the floor would
    /// size the cap for 8 mg when the pouch might be 12, and a cap set below
    /// what someone actually uses is one they blow on day one.
    private func exactEntry(for source: NicotineSource) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("How many mg, exactly?")
                .font(AppFont.text(AppSize.label, .medium))
                .foregroundStyle(AppColor.ink)

            HStack(spacing: AppSpacing.m) {
                stepButton("minus") { adjust(-1, for: source) }

                Text(answers.exactStrengths[source].map { "\($0.clean) mg" } ?? "— mg")
                    .font(AppFont.display(AppSize.unit))
                    .foregroundStyle(answers.exactStrengths[source] == nil ? AppColor.inkFaint : AppColor.ink)
                    .frame(maxWidth: .infinity)

                stepButton("plus") { adjust(1, for: source) }
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

    private func adjust(_ delta: Double, for source: NicotineSource) {
        let floor = answers.strengths[source]?.mg ?? StrengthOption.assumedWhenUnsure(for: source)
        let current = answers.exactStrengths[source] ?? floor
        // Never below the floor the user already chose — they said "or more".
        answers.exactStrengths[source] = max(floor, min(current + delta, 60))
    }

    private var canContinue: Bool {
        !sources.isEmpty
            && sources.allSatisfy { answers.strengths[$0] != nil }
            && answers.sourcesNeedingExactStrength.isEmpty
    }
}

extension Double {
    /// Drops a trailing `.0`, so 3 reads as "3 mg" and 1.5 as "1.5 mg" — the
    /// lozenge strengths make the fractional case real rather than theoretical.
    var clean: String {
        self == rounded() ? String(Int(self)) : String(self)
    }
}
