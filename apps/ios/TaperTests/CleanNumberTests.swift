import Foundation
import Testing
@testable import Taper

/// Covers how the app prints a dose — the one piece of formatting every screen
/// shares, and the only place a milligram figure becomes words.
@MainActor
struct CleanNumberTests {
    @Test("a dose taken more than once prints as a dose, not as a Double")
    func aMultipleDoesNotLeakItsBinary() {
        // 1.2 mg three times. Exact in decimal, not in binary — and the old
        // formatter printed the shortest text that round-trips the *Double*,
        // which is 3.5999999999999996. True of the number and not of the dose,
        // on a row somebody reads to check what they have had today.
        #expect((1.2 * 3).clean == "3.6")
        #expect((0.1 + 0.2).clean == "0.3")
        #expect((2.9 * 3).clean == "8.7")
    }

    @Test("a whole number keeps no decimal point")
    func wholeDosesStayWhole() {
        #expect(3.0.clean == "3")
        #expect(18.0.clean == "18")
        #expect((1.5 * 2).clean == "3", "a multiple that lands whole kept a tail")
        #expect(0.0.clean == "0")
        // Trailing-zero stripping must not eat a round number's own zeros.
        #expect(100.0.clean == "100")
        #expect(20.0.clean == "20")
    }

    @Test("the fractional strengths the app actually sells are kept")
    func realStrengthsSurvive() {
        // The column is `numeric(6, 2)`, and lozenges make the fractional case
        // real rather than theoretical.
        #expect(1.5.clean == "1.5")
        #expect(12.5.clean == "12.5")
        #expect(0.25.clean == "0.25")
    }

    @Test("rounding is to the two decimals the column carries")
    func nothingFinerThanTheColumnIsClaimed() {
        // `mg numeric(6, 2)` cannot hold a third decimal, so printing one
        // would be the screen claiming a precision the record does not have.
        #expect(3.567.clean == "3.57")
        #expect(0.005.clean == "0.01")
    }
}
