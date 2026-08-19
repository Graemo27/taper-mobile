import SwiftUI

/// A selectable row in an onboarding question.
///
/// Selection is an outline and a tick, not a filled card. A brat-green fill was
/// tried and reads far too loud for a list where several rows can be chosen —
/// the accent is reserved for one action, a counting-down number, the current
/// selection on a *small* control, and the live edge of a meter.
struct OptionCard: View {
    let label: String
    /// A second line under the label, for questions where the choice needs a
    /// word about what it is *for*. Absent on the plain lists, which read
    /// better without a subtitle none of the options need.
    var detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(AppFont.text(AppSize.bodyLarge, .medium))
                        .foregroundStyle(AppColor.ink)

                    if let detail {
                        Text(detail)
                            .font(AppFont.text(AppSize.caption))
                            .foregroundStyle(AppColor.inkMuted)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                // A fixed slot either way, so the label's wrap point does not
                // move when a row is chosen.
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.ink)
                    .frame(width: 20, height: 20)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, AppSpacing.xl)
            // Tighter above and below when there are two lines, so a row with a
            // subtitle is the same height as one without rather than half again
            // as tall.
            .padding(.vertical, detail == nil ? AppSpacing.xl : AppSpacing.mPlus)
            .frame(minHeight: 64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large)
                    // Both states draw a border so the row's geometry does not
                    // shift by a point when it is selected.
                    .strokeBorder(
                        isSelected ? AppColor.ink : AppColor.line,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
