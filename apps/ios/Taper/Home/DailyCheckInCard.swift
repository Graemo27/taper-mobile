import SwiftUI

/// L1's daily check-in card: "How were cravings today?" and three words.
///
/// Optional, and drawn that way: no state for "unanswered", no prompt beyond
/// the question, and copy that says skipping is fine. The one thing the card
/// teaches — noticing a craving without acting on it is the skill — is in the
/// subtitle, so it is read even by somebody who never answers.
struct DailyCheckInCard: View {
    @Bindable var record: DayRatingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("How were cravings today?")
                    .font(AppFont.display(AppSize.heading))
                    .foregroundStyle(AppColor.ink)
                Text("Optional — skip freely. Noticing a craving without acting on it is the skill; this is just practice.")
                    .font(AppFont.text(AppSize.label))
                    .lineSpacing(AppLeading.normal - AppSize.label)
                    .foregroundStyle(AppColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AppSpacing.sm) {
                ForEach(DayRating.allCases, id: \.self) { rating in
                    chip(rating)
                }
            }

            if let note = record.failureText {
                Text(note)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.xl)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
    }

    /// Filled when it is the answer, outlined when it is on offer.
    private func chip(_ rating: DayRating) -> some View {
        let isAnswer = record.rating == rating
        return Button {
            Task { await record.tapped(rating) }
        } label: {
            Text(rating.word)
                .font(AppFont.text(AppSize.label, isAnswer ? .medium : .regular))
                .foregroundStyle(AppColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.tap)
                .background {
                    if isAnswer {
                        Capsule().fill(AppColor.accent)
                    } else {
                        Capsule().strokeBorder(AppColor.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.rating.\(rating.rawValue)")
        .accessibilityLabel(rating.word)
        .accessibilityAddTraits(isAnswer ? .isSelected : [])
    }
}
