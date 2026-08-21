import SwiftUI

/// The three places the app goes.
///
/// `plan` is here without a screen behind it. The board draws three tabs and a
/// bar that grows a tab later is one people have to re-learn — so the shape is
/// right from the start and the destination says plainly that it is not built,
/// which is the same bargain every unfinished surface in this app makes.
enum TaperTab: String, CaseIterable, Identifiable {
    case home, log, plan

    var id: String { rawValue }

    /// Lowercase, as the board sets them. Not a sentence, so not capitalised.
    var label: String { rawValue }
}

/// The bar itself.
struct TaperTabBar: View {
    @Binding var selection: TaperTab

    var body: some View {
        HStack(alignment: .top) {
            ForEach(TaperTab.allCases) { tab in
                Button { selection = tab } label: { item(tab) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
                    .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.giant)
        .padding(.top, AppSpacing.m)
        .padding(.bottom, AppSpacing.xxxl)
        .background(AppColor.ground)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColor.line).frame(height: 1)
        }
    }

    private func item(_ tab: TaperTab) -> some View {
        let isCurrent = selection == tab
        return VStack(spacing: 5) {
            TaperTabMark(tab: tab)
                .foregroundStyle(isCurrent ? AppColor.ink : AppColor.inkFaint)
            Text(tab.label)
                .font(AppFont.text(AppSize.micro, isCurrent ? .medium : .regular))
                .foregroundStyle(isCurrent ? AppColor.ink : AppColor.inkFaint)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
    }
}

/// A tab's mark, on the board's 24-unit grid.
///
/// Drawn rather than taken from SF Symbols for the reason the pad's marks are:
/// these are single strokes at one weight, and the system set is neither.
private struct TaperTabMark: View {
    let tab: TaperTab

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            context.stroke(
                path,
                with: .style(.foreground),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 24, height: 24)
    }

    private var path: Path {
        var path = Path()
        switch tab {
        case .home:
            // A roof over a doorway.
            path.move(to: CGPoint(x: 4, y: 10.5))
            path.addLine(to: CGPoint(x: 12, y: 4))
            path.addLine(to: CGPoint(x: 20, y: 10.5))
            path.addLine(to: CGPoint(x: 20, y: 20))
            path.addLine(to: CGPoint(x: 14, y: 21))
            path.addLine(to: CGPoint(x: 14, y: 15))
            path.addLine(to: CGPoint(x: 10, y: 15))
            path.addLine(to: CGPoint(x: 10, y: 21))
            path.addLine(to: CGPoint(x: 4, y: 20))
            path.closeSubpath()
        case .log:
            path.move(to: CGPoint(x: 12, y: 5))
            path.addLine(to: CGPoint(x: 12, y: 19))
            path.move(to: CGPoint(x: 5, y: 12))
            path.addLine(to: CGPoint(x: 19, y: 12))
        case .plan:
            // The descent, as the plan screen draws it.
            path.move(to: CGPoint(x: 4, y: 6))
            path.addCurve(
                to: CGPoint(x: 12, y: 12.5),
                control1: CGPoint(x: 6.7, y: 6),
                control2: CGPoint(x: 9.3, y: 9)
            )
            path.addCurve(
                to: CGPoint(x: 20, y: 18),
                control1: CGPoint(x: 14.7, y: 16),
                control2: CGPoint(x: 17.3, y: 18)
            )
        }
        return path
    }
}
