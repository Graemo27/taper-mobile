import SwiftUI
import Testing
import UIKit
@testable import Taper

/// Guards the two ways a token layer goes wrong quietly.
///
/// The first is drift: these values are transcribed from the Paper file by hand,
/// because nothing exports Paper to Swift, so the only thing standing between a
/// design change and a stale app is a check that names the number.
///
/// The second is fonts. A face can sit in the bundle, be listed in `UIAppFonts`,
/// and still fail to load because the PostScript name is not the filename — and
/// SwiftUI answers that by silently substituting the system face. Nothing throws
/// and nothing logs; the screen simply looks wrong to anyone who knows what it
/// should look like. That is the exact shape of the configuration failure this
/// project has shipped before, so it is asserted rather than assumed.
struct DesignTokenTests {
    // MARK: - The identities the layout depends on

    @Test("the pad grid fills the content width exactly")
    func padGridFillsContentWidth() {
        // Break this and the pad stops reaching the right margin. It is why the
        // key is 110 and why the gap became 16 when the gutter narrowed to 20.
        #expect(3 * AppLayout.key + 2 * AppLayout.padGap == AppLayout.contentWidth)
    }

    @Test("the content width is the screen minus a gutter each side")
    func contentWidthFollowsGutter() {
        #expect(AppLayout.screenWidth - 2 * AppLayout.gutter == AppLayout.contentWidth)
    }

    @Test("the gutter is 20, which the Paper file and the pad arithmetic both assume")
    func gutterIsTwenty() {
        #expect(AppLayout.gutter == 20)
        #expect(AppLayout.contentWidth == 362)
    }

    @Test("tap targets clear the 44pt minimum")
    func tapTargetsAreReachable() {
        #expect(AppLayout.tap >= 44)
        #expect(AppLayout.action >= 44)
        #expect(AppLayout.key >= 44)
    }

    // MARK: - Fonts

    @Test("every registered face loads under the name the tokens use")
    func fontsAreLoadable() {
        for name in [
            AppFont.Face.display,
            AppFont.Face.text,
            AppFont.Face.textMedium,
            AppFont.Face.textSemibold,
        ] {
            let font = UIFont(name: name, size: 17)
            #expect(font != nil, "\(name) did not load — check UIAppFonts and the PostScript name")
            // UIFont falls back rather than failing, so a non-nil result is not
            // enough: confirm it is the face asked for and not a substitute.
            #expect(font?.fontName == name, "\(name) resolved to \(font?.fontName ?? "nil")")
        }
    }

    @Test("the display face is the serif and the text face is not")
    func facesAreNotSwapped() {
        // Cheap guard against the two families being transposed in the tokens,
        // which compiles, loads, and renders every headline in the wrong voice.
        #expect(AppFont.Face.display.hasPrefix("Ginger"))
        #expect(AppFont.Face.text.hasPrefix("LinearGrotesk"))
        #expect(AppFont.Face.textMedium.hasPrefix("LinearGrotesk"))
        #expect(AppFont.Face.textSemibold.hasPrefix("LinearGrotesk"))
    }

    // MARK: - Colour

    @Test("ink on accent is the readable pairing, not white")
    func inkOnAccentIsReadable() {
        // Ink on brat green measures 8.9:1; white measures 1.9:1. The rule is a
        // colour decision, so it is pinned as one rather than left to whoever
        // writes the next button.
        #expect(contrast(AppColor.onAccent, on: AppColor.accent) > 7)
        #expect(contrast(.white, on: AppColor.accent) < 3)
    }

    @Test("ink-faint fails AA on purpose, and ink-muted does not")
    func mutedInkClearsWhatFaintDoesNot() {
        #expect(contrast(AppColor.inkFaint, on: AppColor.ground) < 4.5)
        #expect(contrast(AppColor.inkMuted, on: AppColor.ground) >= 4.5)
    }

    @Test("the two reds sit at opposite ends, so the tint cannot read as a verdict")
    func sourceTintIsNotAVerdict() {
        #expect(contrast(AppColor.ink, on: AppColor.sourceTint) > 10)
        #expect(contrast(AppColor.ink, on: AppColor.over) < 6)
    }

    /// WCAG relative luminance contrast, computed rather than trusted.
    private func contrast(_ a: Color, on b: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &bl, alpha: &alpha)
            func channel(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(bl)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
