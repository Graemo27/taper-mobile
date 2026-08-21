import SwiftUI

/// One key on the pad, as the board draws it: a 110pt square with a mark, a
/// name and the strength it logs.
///
/// The strength sits in a tinted pill whose colour is the ledger — accent for
/// what helps, source-tint for what counts against the day's ceiling. That is
/// the only place the two ledgers differ visually inside a key, and it is
/// deliberately not the label: a key someone taps at speed is read by shape and
/// colour before it is read as words.
struct PadKeyTile: View {
    let key: StoredPadKey

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            if PadKeyMark.isDrawn(key.form) { PadKeyMark(form: key.form) }
            Text(key.label)
                .font(AppFont.text(AppSize.caption, .medium))
                .lineSpacing(AppLeading.tight - AppSize.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.ink)
            strengthPill
        }
        .frame(width: AppLayout.key, height: AppLayout.key)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .strokeBorder(AppColor.line, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.label), \(key.mg.clean) milligrams")
    }

    private var strengthPill: some View {
        Text("\(key.mg.clean) mg")
            .font(AppFont.text(AppSize.nano, .medium))
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(pillTint, in: Capsule())
    }

    /// Accent for treatment, source-tint for what counts against the ceiling.
    private var pillTint: Color {
        key.ledger == .treatment ? AppColor.accentTint : AppColor.sourceTint
    }
}

/// The mark on a key.
///
/// Four forms are drawn from the board — patch, lozenge, pouch, vape — and
/// every other form gets **no mark at all**. That is deliberate rather than
/// unfinished: the board has never drawn a cigarette, a dip, gum, an inhaler
/// or a spray, and a guessed mark would be the app extending a design language
/// it does not own. A neutral placeholder was worse in practice — the first
/// one drew as a circle and was indistinguishable from the lozenge, which is
/// how a stand-in starts impersonating a real thing.
///
/// The paths are the board's, on its own 22-unit grid, scaled at draw time. A
/// `Canvas` rather than composed shapes because the marks are single strokes
/// with exact endpoints, and reproducing those by insetting a `RoundedRectangle`
/// is arithmetic that drifts every time the size changes.
struct PadKeyMark: View {
    let form: PadForm

    /// The board's grid, and the size a mark is drawn at.
    private static let grid: CGFloat = 22
    private static let side: CGFloat = 26
    private static let stroke: CGFloat = 1.6

    /// Whether this form has a mark at all.
    static func isDrawn(_ form: PadForm) -> Bool {
        switch form {
        case .patch, .lozenge, .pouch, .vape: return true
        default: return false
        }
    }

    var body: some View {
        Canvas { context, size in
            let scale = size.width / Self.grid
            context.scaleBy(x: scale, y: scale)
            // Tilted, because a pouch is the one thing here nobody sets down
            // square. Rotated about the grid's centre, as on the board.
            if form == .pouch {
                context.translateBy(x: Self.grid / 2, y: Self.grid / 2)
                context.rotate(by: .degrees(-5))
                context.translateBy(x: -Self.grid / 2, y: -Self.grid / 2)
            }
            let ink = GraphicsContext.Shading.color(AppColor.ink)
            let width = Self.stroke
            context.stroke(outline, with: ink, lineWidth: width)
            context.stroke(
                detail,
                with: ink,
                style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash)
            )
        }
        .frame(width: Self.side, height: Self.side)
    }

    /// The body of the mark.
    private var outline: Path {
        switch form {
        case .patch:
            return Path(roundedRect: CGRect(x: 4, y: 4, width: 14, height: 14), cornerRadius: 4)
        case .lozenge:
            return Path(ellipseIn: CGRect(x: 4.4, y: 4.4, width: 13.2, height: 13.2))
        case .pouch:
            return Path(roundedRect: CGRect(x: 3, y: 7, width: 16, height: 9), cornerRadius: 4.5)
        case .vape:
            return Path(roundedRect: CGRect(x: 8, y: 3, width: 6, height: 16), cornerRadius: 3)
        default:
            return Path()
        }
    }

    /// What crosses it.
    private var detail: Path {
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
        case .pouch:
            path.move(to: CGPoint(x: 7, y: 11.5))
            path.addLine(to: CGPoint(x: 15, y: 11.5))
        case .vape:
            path.move(to: CGPoint(x: 11, y: 6.5))
            path.addLine(to: CGPoint(x: 11, y: 9.5))
        default:
            break
        }
        return path
    }

    /// A near-zero dash on a 3-unit gap, which reads as dots rather than as a
    /// dashed line. Only the two forms that are perforated carry it.
    private var dash: [CGFloat] {
        form == .patch || form == .pouch ? [0.1, 3] : []
    }
}
