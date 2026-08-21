import Foundation
import Testing
@testable import Taper

private func key(_ id: Int, mg: Double = 3, label: String = "Pouches") -> StoredPadKey {
    StoredPadKey(id: id, form: .pouch, label: label, mg: mg, position: 0, ndc: nil)
}

/// Covers what a tap on the pad means.
@MainActor
struct PadSelectionTests {
    @Test("a tap selects one of that key")
    func tappingSelects() {
        let selection = PadSelection()

        selection.tap(key(1))

        #expect(selection.pending?.key.id == 1)
        #expect(selection.pending?.quantity == 1)
    }

    @Test("the same key again counts one more of it")
    func tappingAgainCounts() {
        // What the board's "× 1" is counting. Starting over on every tap would
        // make three pouches three separate trips through the action bar.
        let selection = PadSelection()

        selection.tap(key(1))
        selection.tap(key(1))
        selection.tap(key(1))

        #expect(selection.pending?.quantity == 3)
        #expect(selection.pending?.recap == "Pouches × 3")
    }

    @Test("counting stops where the column stops")
    func tappingPastTwentyHolds() {
        // `check (quantity between 1 and 20)`. Past it the insert is refused,
        // and the refusal arrives after the user believes they have logged.
        let selection = PadSelection()
        for _ in 0..<25 { selection.tap(key(1)) }

        #expect(selection.pending?.quantity == 20)
    }

    @Test("a different key replaces the selection rather than joining it")
    func tappingAnotherKeyStartsOver() {
        // The readout names one thing above one figure. A pad that quietly
        // accumulated two would show a total nobody could account for.
        let selection = PadSelection()

        selection.tap(key(1))
        selection.tap(key(1))
        selection.tap(key(2, label: "Vape"))

        #expect(selection.pending?.key.id == 2)
        #expect(selection.pending?.quantity == 1, "the count carried over to a different key")
    }

    @Test("two keys that look alike are still two keys")
    func identityIsTheRowNotTheLabel() {
        // Somebody may legitimately own two lozenge keys at different
        // strengths, and `pad_keys` has no unique index that would stop it.
        // Counting by anything softer than the row id would merge them.
        let selection = PadSelection()

        selection.tap(key(1, mg: 2, label: "Lozenge"))
        selection.tap(key(2, mg: 4, label: "Lozenge"))

        #expect(selection.pending?.key.id == 2)
        #expect(selection.pending?.quantity == 1)
    }

    @Test("clearing puts the pad back to resting")
    func clearingResets() {
        let selection = PadSelection()
        selection.tap(key(1))

        selection.clear()

        #expect(selection.pending == nil)
    }

    @Test("a cleared pad counts from one again rather than resuming")
    func clearingIsNotAPause() {
        let selection = PadSelection()
        selection.tap(key(1))
        selection.tap(key(1))

        selection.clear()
        selection.tap(key(1))

        #expect(selection.pending?.quantity == 1, "the cleared count came back")
    }
}
