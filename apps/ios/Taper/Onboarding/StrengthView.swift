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
    /// A dose, written the way a person reads one.
    ///
    /// Drops a trailing `.0`, so 3 reads as "3 mg" and 1.5 as "1.5 mg" — the
    /// lozenge strengths make the fractional case real rather than theoretical.
    ///
    /// Rounded to two decimals first, which is the fix for the failure this
    /// used to have. `String(aDouble)` prints the shortest text that
    /// round-trips the *binary* value, and 1.2 mg logged three times is
    /// 3.5999999999999996 — true of the Double and not of the dose. It reached
    /// every screen that shows a total rather than a single strength.
    ///
    /// Two decimals because `mg numeric(6, 2)` cannot hold a third. Printing
    /// one would be the screen claiming a precision the record does not have.
    var clean: String {
        // Formatted rather than interpolated. Interpolation asks the Double
        // what it is; this asks what is worth saying about it — and the
        // rounding to two places falls out of the format rather than needing a
        // step of its own. An earlier version rounded first as well, and
        // mutation testing showed the extra step changed no answer.
        //
        // **No locale, deliberately, and it was checked.** The strip loop
        // below only stops on a period, so a comma separator would leave "3,"
        // standing where a whole number belongs. Driven under fr_FR and de_DE,
        // where `Locale.current.decimalSeparator` really is a comma: this line
        // still produces "3.00". `String(format:)` without a locale does not
        // localize.
        //
        // Passing one explicitly is the obvious "fix" and is worse. It takes
        // the localized formatting path, which rounds a half to even — 0.005
        // becomes "0" rather than "0.01" — and `mg numeric(6, 2)` rounds half
        // away from zero, so the screen would stop agreeing with the column it
        // is reading.
        var text = String(format: "%.2f", self)
        // Trailing zeros go, so 3.60 reads as "3.6" and 3.00 as "3". The point
        // stops the loop before it can eat a whole number's own zeros — "100"
        // survives because "100." is not a suffix of "0".
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
