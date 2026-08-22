import SwiftUI

/// The way back out of a pushed screen, named for where it goes.
///
/// Shared by the day's list and the check-in it opens, which are the only two
/// screens in the app you navigate *to*. The label is the destination rather
/// than the word "Back" — that is the iOS convention and the useful half: it
/// says where the tap lands, which matters most on the second level, where
/// "Today" and "Home" are one tap apart and mean different things.
///
/// An SF Symbol, unlike the nicotine marks. Those are the board's own drawings
/// at one stroke weight and the system set is not them; a back chevron is
/// furniture, and the system one comes with Dynamic Type and the right optical
/// weight for free.
struct BackControl: View {
    /// Where the tap goes — "Home", "Today".
    let destination: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text(destination)
                    .font(AppFont.text(AppSize.body))
                    .foregroundStyle(AppColor.ink)
            }
            .contentShape(Rectangle())
            .frame(height: AppLayout.tap, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(destination.lowercased())")
    }
}
