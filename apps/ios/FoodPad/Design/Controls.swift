import SwiftUI

/// Journal, Search and Food detail all show a button reading "Try again", so the
/// visible label cannot say which "again" it means. Only the spoken label can.
struct RetryButton: View {
    let spokenLabel: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Try again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.brand)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier(identifier)
    }
}

/// Wraps chip to chip. An `HStack` wraps the text *inside* each chip instead, so
/// at accessibility sizes "Vitamin E" breaks across two lines within its pill.
struct ChipFlow: Layout {
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(across: proposal.width ?? .infinity, subviews)
        let width = rows.map { span($0, subviews) }.max() ?? 0
        return CGSize(width: width, height: stacked(rows, subviews))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(across: bounds.width, subviews) {
            var x = bounds.minX
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            y += spacing
        }
    }

    private func rows(across width: Double, _ subviews: Subviews) -> [[Int]] {
        var rows: [[Int]] = []
        var row: [Int] = []
        var x = 0.0
        for index in subviews.indices {
            let chip = subviews[index].sizeThatFits(.unspecified).width
            if !row.isEmpty && x + chip > width {
                rows.append(row)
                row = []
                x = 0
            }
            row.append(index)
            x += chip + spacing
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    private func span(_ row: [Int], _ subviews: Subviews) -> Double {
        max(0, row.reduce(-spacing) { $0 + spacing + subviews[$1].sizeThatFits(.unspecified).width })
    }

    private func stacked(_ rows: [[Int]], _ subviews: Subviews) -> Double {
        max(0, rows.reduce(-spacing) { total, row in
            total + spacing + (row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0)
        })
    }
}
