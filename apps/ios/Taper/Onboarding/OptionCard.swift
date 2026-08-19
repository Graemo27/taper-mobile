import SwiftUI

/// A selectable row in an onboarding question.
///
/// Selection is an outline and a tick, not a filled card. A brat-green fill was
/// tried and reads far too loud for a list where several rows can be chosen —
/// the accent is reserved for one action, a counting-down number, the current
/// selection on a *small* control, and the live edge of a meter.
struct OptionCard: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.m) {
                Text(label)
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
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
            .padding(AppSpacing.xl)
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
