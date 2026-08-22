import Foundation
import SwiftUI
import Testing
@testable import Taper

/// Covers which nicotine forms the app has a mark for, and that a form claiming
/// one actually draws something.
@MainActor
struct NicotineMarkTests {
    @Test("the five forms the board draws have marks, and no others do")
    func onlyTheBoardsFormsAreDrawn() {
        // Gum is the one worth naming. It is one of exactly three treatments
        // this app offers, and it drew nothing at all until the board's log
        // rows turned out to have a mark for it — so a third of everyone
        // tapering had a blank key while patch and lozenge had marks.
        let drawn: Set<PadForm> = [.patch, .lozenge, .gum, .pouch, .vape]

        for form in PadForm.allCases {
            #expect(
                NicotineMark.isDrawn(form) == drawn.contains(form),
                "\(form.rawValue) disagrees with the board about whether it has a mark"
            )
        }

        // Cigarettes are the most common thing anyone quits, so the most-used
        // key in the app is still one of the ones with no mark. Pinned rather
        // than left as a comment: adding a mark should be a deliberate edit
        // against the board, not something that drifts in.
        #expect(!NicotineMark.isDrawn(.cigarette))
    }

    @Test("a form that claims a mark draws one")
    func aClaimedMarkIsNotEmpty() {
        // `isDrawn` and the paths are two answers to one question, and the way
        // they go wrong is a form being added to the list and never given a
        // shape — which draws as a blank key rather than as anything failing.
        for form in PadForm.allCases where NicotineMark.isDrawn(form) {
            let mark = NicotineMark(form: form)
            #expect(!mark.outline.isEmpty, "\(form.rawValue) claims a mark but has no outline")
            #expect(!mark.detail.isEmpty, "\(form.rawValue) claims a mark but has nothing crossing it")
        }
    }

    @Test("a form with no mark draws nothing at all")
    func anUndrawnFormIsBlank() {
        // Never a placeholder. The first attempt at one drew as a circle and
        // was indistinguishable from the lozenge, which is how a stand-in
        // starts impersonating a real thing.
        for form in PadForm.allCases where !NicotineMark.isDrawn(form) {
            let mark = NicotineMark(form: form)
            #expect(mark.outline.isEmpty, "\(form.rawValue) has no mark but drew an outline")
            #expect(mark.detail.isEmpty, "\(form.rawValue) has no mark but drew a detail")
        }
    }

    @Test("gum is square where the lozenge is round")
    func gumIsNotASecondLozenge() {
        // They sit on almost the same footprint — 13 units against 13.2 — so
        // the corner is the only thing telling them apart. A gum drawn round
        // would be a second lozenge on a surface built to be hit without
        // looking, which is the stand-in-impersonating-a-real-thing failure
        // this mark set exists to avoid.
        //
        // Asked of the geometry rather than compared to a literal path, which
        // would only restate the implementation back to itself.
        let corner = CGPoint(x: 6, y: 6)
        #expect(NicotineMark(form: .gum).outline.contains(corner), "gum lost its corners")
        #expect(
            !NicotineMark(form: .lozenge).outline.contains(corner),
            "the lozenge grew corners, so the two marks now read the same at a glance"
        )
    }

    @Test("only the perforated forms are dotted")
    func theDashBelongsToTwoForms() {
        for form in PadForm.allCases {
            let dotted = !NicotineMark(form: form).dash.isEmpty
            #expect(dotted == (form == .patch || form == .pouch), "\(form.rawValue) is dotted wrongly")
        }
    }
}
