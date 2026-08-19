import SwiftUI

// Primitives. Views consume only the semantic aliases below — a call site that
// reaches for a ramp step has skipped the layer where meaning lives, and the
// next re-brand will miss it. This file is the one place both names appear.
//
// Kept in step with the Paper file `Taper` by hand. There is no export from
// Paper to Swift, so the honest description is "transcribed", and the guard
// against drift is `DesignTokenTests`, which pins every value that a screen
// would visibly get wrong.
private enum Paper {
    static let p0 = Color(hex: "FFFFFF")
    static let p50 = Color(hex: "F8F7F4")
    static let p100 = Color(hex: "ECEAE5")
    static let p200 = Color(hex: "E4E1DC")
    static let p300 = Color(hex: "CAC6BF")
    static let p400 = Color(hex: "A2A09C")
    static let p500 = Color(hex: "6C6A66")
    static let p900 = Color(hex: "1C1C1A")
}

private enum Brat {
    static let b50 = Color(hex: "EAF6D2")
    static let b100 = Color(hex: "D6E9B0")
    static let b500 = Color(hex: "8ACE00")
    static let b600 = Color(hex: "74AD00")
    static let b900 = Color(hex: "393E2E")
}

private enum Support {
    static let periwinkle100 = Color(hex: "D9DEFB")
    static let periwinkle700 = Color(hex: "4E4E5A")
    static let amber50 = Color(hex: "FFFBE6")
    static let amber100 = Color(hex: "FAEE9E")
    static let amber500 = Color(hex: "D0BB00")
    static let amber600 = Color(hex: "B09E00")
    static let amber700 = Color(hex: "7A6B14")
    static let amber800 = Color(hex: "655A15")
    static let red50 = Color(hex: "F7DEDE")
    static let red500 = Color(hex: "C43C3C")
}

/// The only colour names a view may use.
///
/// Light theme only — there is no dark palette, and adding one is a design
/// decision rather than a missing feature.
enum AppColor {
    static let ground = Paper.p50
    static let surface = Paper.p0
    static let sunken = Paper.p100
    static let line = Paper.p200
    static let lineStrong = Paper.p300
    static let ink = Paper.p900
    static let inkMuted = Paper.p500
    /// Fails AA at 2.4:1, deliberately. Legal for inactive tab labels, footnotes
    /// and a dimmed zero — never for a sentence someone must read to act.
    static let inkFaint = Paper.p400
    static let inkInverse = Paper.p0

    static let accent = Brat.b500
    static let accentEdge = Brat.b600
    static let accentTint = Brat.b50
    static let accentTintStrong = Brat.b100
    /// Ink on accent reads 8.9:1; white reads 1.9:1. Never white.
    static let onAccent = Paper.p900
    static let onAccentTint = Brat.b900
    static let onAccentMuted = Paper.p900.opacity(0.7)
    static let veilOnAccent = Paper.p0.opacity(0.55)

    static let secondary = Support.periwinkle100
    static let onSecondary = Paper.p900
    static let onSecondaryMuted = Support.periwinkle700

    static let cautionSurface = Support.amber50
    static let cautionTint = Support.amber100
    static let cautionFill = Support.amber500
    static let cautionEdge = Support.amber600
    static let cautionMark = Support.amber700
    static let cautionInk = Support.amber800
    static let onCautionFill = Paper.p900
    static let onCautionMuted = Paper.p900.opacity(0.7)
    static let veilOnCaution = Paper.p0.opacity(0.55)

    /// Full-strength red means one thing: over the cap. The tint below is the
    /// quieter job — marking a key as something being quit rather than a
    /// treatment. Keeping them at opposite ends is what stops the second
    /// reading as the first.
    static let over = Support.red500
    static let sourceTint = Support.red50

    static let trackOnTile = Paper.p900.opacity(0.12)
}

/// Type. Two families, one job each: Ginger says the number, Linear Grotesk
/// says everything else.
enum AppFont {
    /// PostScript names, not filenames. A font can sit in the bundle and still
    /// fail to load under a guessed name, which renders as a silent fallback to
    /// the system face — see `DesignTokenTests.fontsAreLoadable`.
    enum Face {
        static let display = "GingerRegular"
        static let text = "LinearGrotesk-Regular"
        static let textMedium = "LinearGrotesk-Medium"
        static let textSemibold = "LinearGrotesk-SemiBold"
    }

    /// Ginger ships Regular only, so a display style never asks for a weight.
    static func display(_ size: CGFloat) -> Font { .custom(Face.display, size: size) }

    static func text(_ size: CGFloat, _ weight: TextWeight = .regular) -> Font {
        .custom(weight.face, size: size)
    }

    enum TextWeight {
        case regular, medium, semibold

        var face: String {
            switch self {
            case .regular: return Face.text
            case .medium: return Face.textMedium
            case .semibold: return Face.textSemibold
            }
        }
    }
}

/// Font sizes, named for the job rather than the number.
enum AppSize {
    static let nano: CGFloat = 11
    static let micro: CGFloat = 12
    static let caption: CGFloat = 13
    static let label: CGFloat = 14
    static let body: CGFloat = 15
    static let bodyLarge: CGFloat = 16
    static let unitSmall: CGFloat = 18
    static let unit: CGFloat = 22
    static let heading: CGFloat = 24
    static let title: CGFloat = 26
    static let display: CGFloat = 30
    static let metric: CGFloat = 40
    static let figure: CGFloat = 64
    static let hero: CGFloat = 76
}

/// Line heights, as absolute values. SwiftUI has no line-height modifier, so
/// these are applied through `.lineSpacing(_ - fontSize)` at the call site.
enum AppLeading {
    static let nano: CGFloat = 14
    static let tight: CGFloat = 16
    static let snug: CGFloat = 18
    static let normal: CGFloat = 20
    static let relaxed: CGFloat = 22
    static let unit: CGFloat = 28
    static let heading: CGFloat = 30
    static let title: CGFloat = 32
    static let display: CGFloat = 36
    static let metric: CGFloat = 42
    static let figure: CGFloat = 64
    static let hero: CGFloat = 76
}

/// Letter spacing. Three values, and open tracking only ever appears on small
/// caps eyebrows.
enum AppTracking {
    static let normal: CGFloat = 0
    static func eyebrow(_ size: CGFloat) -> CGFloat { size * 0.06 }
    static func eyebrowWide(_ size: CGFloat) -> CGFloat { size * 0.08 }
}

/// Spacing, on a 2px base and a 4px rhythm.
enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let sm: CGFloat = 8
    static let smPlus: CGFloat = 10
    static let m: CGFloat = 12
    static let mPlus: CGFloat = 14
    static let l: CGFloat = 16
    static let lPlus: CGFloat = 18
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 28
    static let huge: CGFloat = 32
    static let giant: CGFloat = 48
}

/// Fixed sizes that carry meaning rather than taste.
enum AppLayout {
    /// The horizontal margin on every screen. Load-bearing twice over: it sets
    /// the content width, and the pad's arithmetic depends on both. Changing it
    /// means changing `contentWidth` and the pad gap together, or the key grid
    /// stops filling the row.
    static let gutter: CGFloat = 20
    static let screenWidth: CGFloat = 402
    /// screenWidth − 2 × gutter. Any self-centring card is exactly this wide.
    static let contentWidth: CGFloat = 362

    /// 3 × key + 2 × padGap == contentWidth. That equality is why the key is
    /// 110 and why the gap is 16; break it and the pad no longer fills its row.
    static let key: CGFloat = 110
    static let padGap: CGFloat = 16

    static let tap: CGFloat = 44
    static let action: CGFloat = 56
    static let tile: CGFloat = 190
}

/// Corner radii. Shape carries meaning here: a pill is an action, a panel is a
/// surface you read.
enum AppRadius {
    static let panel: CGFloat = 4
    static let small: CGFloat = 12
    static let medium: CGFloat = 14
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 20
    static let full: CGFloat = .infinity
}

private extension Color {
    /// Six-digit RGB only. Force-unwrapped deliberately: every caller is a
    /// literal in this file, so a bad value is a typo caught the first time the
    /// app runs, not a condition to handle at runtime.
    init(hex: String) {
        let value = UInt64(hex, radix: 16)!
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}
