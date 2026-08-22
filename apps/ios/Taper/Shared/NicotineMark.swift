import SwiftUI

/// The board's mark for a nicotine form, on its own 22-unit grid.
///
/// Five forms are drawn — patch, lozenge, gum, pouch, vape — and every other
/// form gets **no mark at all**. That is deliberate rather than unfinished: as
/// of 2026-08 the board has no cigarette, dip, inhaler or spray, and a guessed
/// mark would be the app extending a design language it does not own. A neutral
/// placeholder was worse in practice — the first one drew as a circle and was
/// indistinguishable from the lozenge, which is how a stand-in starts
/// impersonating a real thing.
///
/// **Dated, because the sentence above has been wrong before.** It used to name
/// gum in that list — and was wrong the day it was written, because the mark
/// was already on the board's log rows and only the pad's artboard had been
/// looked at. Nothing in this repo can notice when a Paper file changes, so the
/// list is a claim about another tool and has to be checked against it rather
/// than trusted. `NicotineMarkTests` pins what the app currently believes.
///
/// Drawn square, with no tilt of its own. Two surfaces compose these marks
/// differently — a pad key leans the pouch, the log's rows lean the whole tile
/// they sit in — so the shape lives here and the angle belongs to the caller. A
/// mark that carried its own lean would arrive at the second one already
/// crooked and be tilted twice.
///
/// A `Canvas` rather than composed shapes because the marks are single strokes
/// with exact endpoints, and reproducing those by insetting a `RoundedRectangle`
/// is arithmetic that drifts every time the size changes.
struct NicotineMark: View {
    let form: PadForm
    /// How big to draw it. The board sets a pad key's mark at 26 and a log
    /// row's at 22; the grid is the same either way, so only the scale differs.
    var side: CGFloat = 26

    /// The board's grid. Every coordinate below is in these units.
    private static let grid: CGFloat = 22
    private static let stroke: CGFloat = 1.6

    /// Whether this form has a mark at all.
    static func isDrawn(_ form: PadForm) -> Bool {
        switch form {
        case .patch, .lozenge, .gum, .pouch, .vape: return true
        case .inhaler, .spray, .cigarette, .dip, .other: return false
        }
    }

    var body: some View {
        Canvas { context, size in
            let scale = size.width / Self.grid
            context.scaleBy(x: scale, y: scale)
            let ink = GraphicsContext.Shading.color(AppColor.ink)
            context.stroke(outline, with: ink, lineWidth: Self.stroke)
            context.stroke(
                detail,
                with: ink,
                style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round, dash: dash)
            )
        }
        .frame(width: side, height: side)
    }

    /// The body of the mark.
    var outline: Path {
        switch form {
        case .patch:
            return Path(roundedRect: CGRect(x: 4, y: 4, width: 14, height: 14), cornerRadius: 4)
        case .lozenge:
            return Path(ellipseIn: CGRect(x: 4.4, y: 4.4, width: 13.2, height: 13.2))
        case .gum:
            // Square where the lozenge is round, on almost the same footprint.
            // That is the whole distinction between the two on the board, and
            // it is why neither can be drawn a little more like the other.
            return Path(roundedRect: CGRect(x: 4.5, y: 4.5, width: 13, height: 13), cornerRadius: 4)
        case .pouch:
            return Path(roundedRect: CGRect(x: 3, y: 7, width: 16, height: 9), cornerRadius: 4.5)
        case .vape:
            return Path(roundedRect: CGRect(x: 8, y: 3, width: 6, height: 16), cornerRadius: 3)
        case .inhaler, .spray, .cigarette, .dip, .other:
            return Path()
        }
    }

    /// What crosses it.
    var detail: Path {
        var path = Path()
        switch form {
        case .patch:
            for y in [8.5, 13.5] as [CGFloat] {
                path.move(to: CGPoint(x: 8, y: y))
                path.addLine(to: CGPoint(x: 14, y: y))
            }
        case .lozenge:
            path.move(to: CGPoint(x: 7.6, y: 11))
            path.addLine(to: CGPoint(x: 14.4, y: 11))
        case .gum:
            path.move(to: CGPoint(x: 8, y: 11))
            path.addLine(to: CGPoint(x: 14, y: 11))
        case .pouch:
            path.move(to: CGPoint(x: 7, y: 11.5))
            path.addLine(to: CGPoint(x: 15, y: 11.5))
        case .vape:
            path.move(to: CGPoint(x: 11, y: 6.5))
            path.addLine(to: CGPoint(x: 11, y: 9.5))
        case .inhaler, .spray, .cigarette, .dip, .other:
            break
        }
        return path
    }

    /// A near-zero dash on a 3-unit gap, which reads as dots rather than as a
    /// dashed line. Only the two forms that are perforated carry it.
    var dash: [CGFloat] {
        form == .patch || form == .pouch ? [0.1, 3] : []
    }
}
