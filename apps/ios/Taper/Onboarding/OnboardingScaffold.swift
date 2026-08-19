import SwiftUI

/// The frame every onboarding screen sits in.
///
/// Twelve screens share one layout — eyebrow, progress, a serif question, the
/// answer area, and a CTA pinned to the bottom — so it is written once here.
/// The alternative is twelve near-copies that drift apart at the third change,
/// which is how the spacing between screens stops matching.
struct OnboardingScaffold<Content: View>: View {
    let section: String
    let progress: OnboardingProgress
    let question: String
    let helper: String?
    let cta: String
    /// Nil disables the button rather than hiding it. A CTA that appears once an
    /// answer is given moves the whole screen under the reader's thumb.
    let onContinue: (() -> Void)?
    let onBack: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navigation
            OnboardingProgressBar(progress: progress)
            questionBlock

            ScrollView {
                content
                    .padding(.top, AppSpacing.xxl)
                    // Clears the CTA below. Without it the last answer sits
                    // flush against the button and reads as cut off.
                    .padding(.bottom, AppSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)

            continueButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            Button { onBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.ink)
                    .frame(width: 36, height: 36)
            }
            .opacity(onBack == nil ? 0 : 1)
            .disabled(onBack == nil)
            .accessibilityLabel("Back")

            Text(section.uppercased())
                .font(AppFont.text(AppSize.micro, .medium))
                .tracking(AppTracking.eyebrowWide(AppSize.micro))
                .foregroundStyle(AppColor.inkMuted)
                .frame(maxWidth: .infinity)

            // Balances the chevron so the eyebrow is centred on the screen
            // rather than on the space left over beside it.
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.smPlus)
    }

    private var questionBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smPlus) {
            Text(question)
                .font(AppFont.display(AppSize.display))
                .lineSpacing(AppLeading.display - AppSize.display)
                .foregroundStyle(AppColor.ink)

            if let helper {
                Text(helper)
                    .font(AppFont.text(AppSize.body))
                    .lineSpacing(AppLeading.relaxed - AppSize.body)
                    .foregroundStyle(AppColor.inkMuted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.xxxl)
    }

    private var continueButton: some View {
        Button { onContinue?() } label: {
            Text(cta)
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(AppColor.ink, in: Capsule())
        }
        .disabled(onContinue == nil)
        .opacity(onContinue == nil ? 0.35 : 1)
        .padding(.horizontal, AppLayout.gutter)
        .padding(.bottom, AppSpacing.huge)
    }
}

/// How far through onboarding a screen sits, as a section index and a fraction.
///
/// Sections rather than a single bar because twelve steps on one track reads as
/// barely moving. Three groups of four move visibly, which is the only thing a
/// progress indicator is for.
struct OnboardingProgress: Equatable {
    let section: Int
    let sectionCount: Int
    /// 0...1 through the current section.
    let fraction: Double

    static let sections = 3
}

/// The segmented track under the eyebrow.
struct OnboardingProgressBar: View {
    let progress: OnboardingProgress

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0 ..< progress.sectionCount, id: \.self) { index in
                GeometryReader { geometry in
                    Capsule()
                        .fill(AppColor.sunken)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(AppColor.ink)
                                .frame(width: geometry.size.width * fill(for: index))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.mPlus)
        .accessibilityElement()
        .accessibilityLabel("Step \(progress.section + 1) of \(progress.sectionCount)")
    }

    /// Exposed for tests. The clamping here is the whole behaviour — a
    /// fraction outside 0...1 would otherwise draw a segment past its track or
    /// backwards — and it is not observable from a rendered view.
    func fillForTesting(_ index: Int) -> Double { fill(for: index) }

    private func fill(for index: Int) -> Double {
        if index < progress.section { return 1 }
        if index > progress.section { return 0 }
        return min(max(progress.fraction, 0), 1)
    }
}
