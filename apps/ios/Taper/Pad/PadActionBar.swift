import SwiftUI

/// The foot of L3: clear what is selected, or log it.
///
/// Two buttons rather than one that changes meaning. Clearing and committing
/// are opposite intentions and a pad is tapped at speed — a single control that
/// did both depending on state is one people would hit wrong.
struct PadActionBar: View {
    let title: String
    let isEnabled: Bool
    let onClear: () -> Void
    let onCheckIn: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            Button(action: onClear) {
                Text("Clear")
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
                    .padding(.horizontal, AppSpacing.xxl)
                    .frame(height: AppLayout.action)
                    .background(AppColor.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(AppColor.line, lineWidth: 1) }
            }
            .disabled(!isEnabled)

            Button(action: onCheckIn) {
                Text(title)
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.inkInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppLayout.action)
                    .background(AppColor.ink, in: Capsule())
            }
            .disabled(!isEnabled)
        }
        // Dimmed together. Clear with nothing selected does nothing, and a
        // control that responds to a tap by doing nothing is one people press
        // twice before deciding the app is broken.
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

#Preview {
    VStack(spacing: AppSpacing.l) {
        PadActionBar(title: "Check in · 3 mg", isEnabled: true, onClear: {}, onCheckIn: {})
        PadActionBar(title: "Check in", isEnabled: false, onClear: {}, onCheckIn: {})
    }
    .padding(.horizontal, AppLayout.gutter)
}
