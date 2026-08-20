import SwiftUI

/// L0 — the question asked before anything else.
///
/// The app tracks a drug. It sells nothing and ships nothing, so this is an
/// honesty gate rather than an enforcement one, and it is written that way: the
/// refusal is a sentence rather than a lockout, and a wrong answer is
/// correctable. What it must not do is guess — every verdict on screen comes
/// from `AgeGate`, including the one that says nothing yet.
struct AgeGateView: View {
    let onVerified: () -> Void
    let onUnderage: () -> Void
    /// Injected so the boundary this screen exists for can be driven.
    var today: () -> Date = { Date() }

    @State private var entry = BirthdateEntry()
    @FocusState private var focus: Field?

    private enum Field { case month, day, year }

    private var verdict: AgeGate.Verdict {
        AgeGate.verdict(for: entry, on: today())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("taper")
                .font(AppFont.display(AppSize.heading))
                .foregroundStyle(AppColor.ink)
                .padding(.top, AppSpacing.m)

            mark.padding(.top, AppSpacing.giant)
            claim.padding(.top, AppSpacing.l)
            birthdate.padding(.top, AppSpacing.huge)

            Spacer(minLength: AppSpacing.xl)

            actions
            finePrint.padding(.top, AppSpacing.xxl)
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.bottom, AppSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
        .onAppear { focus = .month }
    }

    private var mark: some View {
        HStack(alignment: .center, spacing: AppSpacing.mPlus) {
            Text("18+")
                .font(AppFont.display(AppSize.mark))
                .foregroundStyle(AppColor.ink)

            Text("adults only")
                .font(AppFont.text(AppSize.caption, .medium))
                .foregroundStyle(AppColor.onAccent)
                .padding(.horizontal, AppSpacing.mPlus)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColor.accent, in: Capsule())
                .rotationEffect(.degrees(-6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eighteen and over. Adults only.")
    }

    private var claim: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            Text("This app tracks nicotine.")
                .font(AppFont.display(AppSize.title))
                .lineSpacing(AppLeading.title - AppSize.title)
                .foregroundStyle(AppColor.ink)

            Text("""
            It exists to help you quit — but it's still about a drug, so it's for adults. \
            Enter your birthdate to keep going.
            """)
                .font(AppFont.text(AppSize.body))
                .lineSpacing(AppLeading.relaxed - AppSize.body)
                .foregroundStyle(AppColor.inkMuted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var birthdate: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Birthdate")
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)

            HStack(spacing: AppSpacing.smPlus) {
                box($entry.month, "MM", .month, width: 92, limit: 2)
                box($entry.day, "DD", .day, width: 92, limit: 2)
                box($entry.year, "YYYY", .year, width: nil, limit: 4)
            }

            // Says what actually happens, which is less than the board's
            // caption promised. Only the answer is kept, so there is no
            // birthdate on the device to be private about.
            Text(message ?? "Your birthdate isn't stored or sent anywhere — only the answer, on this device.")
                .font(AppFont.text(AppSize.micro))
                .foregroundStyle(message == nil ? AppColor.inkFaint : AppColor.cautionInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What to say under the fields, or nil while there is nothing to say.
    ///
    /// Silence while the entry is incomplete is the point. An error under
    /// someone who is halfway through their birth year is a complaint about
    /// nothing, and it arrives before they could possibly have finished.
    private var message: String? {
        switch verdict {
        case .incomplete, .adult: return nil
        case .unreadable: return "That isn't a date we can read. Check the month, day and year."
        case .underage: return "You need to be 18 to use Taper."
        }
    }

    private func box(
        _ text: Binding<String>,
        _ placeholder: String,
        _ field: Field,
        width: CGFloat?,
        limit: Int
    ) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(AppColor.inkFaint))
            .font(AppFont.display(AppSize.heading))
            .foregroundStyle(AppColor.ink)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .focused($focus, equals: field)
            .frame(width: width, height: 60)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .strokeBorder(
                        focus == field ? AppColor.ink : AppColor.line,
                        lineWidth: focus == field ? 1.5 : 1
                    )
            }
            .accessibilityLabel(placeholder == "MM" ? "Month" : placeholder == "DD" ? "Day" : "Year")
            .onChange(of: text.wrappedValue) { _, new in
                // Digits only, and no more than the box holds. A date field
                // that accepts letters produces an unreadable verdict for an
                // input the control should never have taken.
                let digits = String(new.filter(\.isNumber).prefix(limit))
                if digits != new { text.wrappedValue = digits }
                if digits.count == limit { advance(from: field) }
            }
    }

    private func advance(from field: Field) {
        switch field {
        case .month: focus = .day
        case .day: focus = .year
        case .year: focus = nil
        }
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.lPlus) {
            // Disabled rather than hidden, so the button does not appear under
            // the reader's thumb the moment the last digit lands.
            OnboardingCTA(
                title: "I'm 18 or older",
                action: verdict == .adult ? onVerified : nil,
                bottomPadding: 0
            )

            Button(action: onUnderage) {
                Text("I'm not 18 yet")
                    .font(AppFont.text(AppSize.body, .medium))
                    .foregroundStyle(AppColor.inkMuted)
            }
        }
    }

    private var finePrint: some View {
        Text("""
        Taper is a habit tracker — not medical advice, and not a store. Nothing here sells or \
        ships nicotine. If you're under 18, the honest move is to close the app.
        """)
            .font(AppFont.text(AppSize.nano))
            .lineSpacing(AppLeading.tight - AppSize.nano)
            .foregroundStyle(AppColor.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Where someone who is not old enough lands.
///
/// A sentence, not a lockout. The gate is an honesty check — anyone can retype
/// a year — so pretending otherwise would be theatre, and the way back exists
/// because the commonest reason to arrive here is a typo.
struct UnderageView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            Spacer(minLength: 0)

            Text("Come back when you're 18.")
                .font(AppFont.display(AppSize.title))
                .lineSpacing(AppLeading.title - AppSize.title)
                .foregroundStyle(AppColor.ink)

            Text("""
            Taper is built for adults who are trying to stop. It'll still be here. If you got \
            here by mistyping your birthdate, you can go back and fix it.
            """)
                .font(AppFont.text(AppSize.body))
                .lineSpacing(AppLeading.relaxed - AppSize.body)
                .foregroundStyle(AppColor.inkMuted)

            Spacer(minLength: 0)

            Button(action: onBack) {
                Text("I mistyped my birthdate")
                    .font(AppFont.text(AppSize.body, .medium))
                    .foregroundStyle(AppColor.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AppLayout.gutter)
        .padding(.bottom, AppSpacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppColor.ground)
    }
}

#Preview {
    AgeGateView(onVerified: {}, onUnderage: {})
}
