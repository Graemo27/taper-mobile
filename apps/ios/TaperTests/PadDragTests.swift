import CoreGraphics
import Testing
@testable import Taper

/// Covers where a dragged key lands. The pad's geometry is fixed, so this is
/// arithmetic — and arithmetic is checkable without a screen.
struct PadDragTests {
    private let step = PadDrag.step.width

    @Test("a key swaps once it is more than halfway onto its neighbour")
    func theEyeDecidesBeforeTheEdgeDoes() {
        // Truncating instead would mean a key only moves once fully clear of
        // the one beside it, which reads as the pad needing an extra shove.
        #expect(PadDrag.target(from: 0, translation: .init(width: step * 0.49, height: 0),
                               count: 3) == 0)
        #expect(PadDrag.target(from: 0, translation: .init(width: step * 0.51, height: 0),
                               count: 3) == 1)
        #expect(PadDrag.target(from: 2, translation: .init(width: -step * 0.51, height: 0),
                               count: 3) == 1)
    }

    @Test("sideways is not a way down")
    func aRowIsOnlyThreeWide() {
        // Added linearly, a drag two seats right from the end of a row walked
        // into the next one — the key changing rows while the finger never
        // left its own. The column is clamped to the row it is in.
        #expect(PadDrag.target(from: 2, translation: .init(width: step, height: 0),
                               count: 6) == 2, "a key left its row without going down")
        #expect(PadDrag.target(from: 1, translation: .init(width: step * 2, height: 0),
                               count: 6) == 2)
        #expect(PadDrag.target(from: 3, translation: .init(width: -step, height: 0),
                               count: 6) == 3, "a key wrapped backwards into the row above")
        // Down is still down, from any column.
        #expect(PadDrag.target(from: 2, translation: .init(width: 0, height: step),
                               count: 6) == 5)
    }

    @Test("a row down is three keys along")
    func theGridIsThreeWide() {
        #expect(PadDrag.target(from: 0, translation: .init(width: 0, height: step),
                               count: 6) == 3)
        #expect(PadDrag.target(from: 4, translation: .init(width: 0, height: -step),
                               count: 6) == 1)
        #expect(PadDrag.target(from: 0, translation: .init(width: step, height: step),
                               count: 6) == 4)
    }

    @Test("a thumb that keeps going lands on the end, not off it")
    func aDragCannotLoseAKey() {
        #expect(PadDrag.target(from: 0, translation: .init(width: step * 40, height: 0),
                               count: 3) == 2)
        #expect(PadDrag.target(from: 2, translation: .init(width: -step * 40, height: 0),
                               count: 3) == 0)
        #expect(PadDrag.target(from: 0, translation: .zero, count: 0) == 0)
    }

    @Test("moving a key slides the others, rather than trading places")
    func aMoveIsNotASwap() {
        // Dragging the first key to the end should leave the rest in order.
        // A swap would put the last key first, which is a second change
        // nobody asked for.
        #expect(PadDrag.reordered([1, 2, 3, 4], moving: 1, to: 3) == [2, 3, 4, 1])
        #expect(PadDrag.reordered([1, 2, 3, 4], moving: 4, to: 0) == [4, 1, 2, 3])
        #expect(PadDrag.reordered([1, 2, 3], moving: 2, to: 2) == [1, 3, 2])
    }

    @Test("a key the ledger does not hold leaves it alone")
    func anUnknownKeyChangesNothing() {
        #expect(PadDrag.reordered([1, 2, 3], moving: 9, to: 0) == [1, 2, 3])
    }
}
