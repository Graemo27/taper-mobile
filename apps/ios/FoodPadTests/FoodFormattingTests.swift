import XCTest
@testable import FoodPad

final class FoodFormattingTests: XCTestCase {
    func testServingSummaryPortsEveryNamedFDCLabelCase() {
        let cases: [(String, Double, Double, String)] = [
            ("1 slice", 15, 2, "2 slices · 30 g"),
            ("4 slices", 15, 2, "8 slices · 30 g"),
            ("1 pita, large (6-1/2\" dia)", 64, 2, "2 pitas, large · 6-1/2\" dia · 128 g"),
            ("3/4 cup", 80, 2, "1.5 cups · 160 g"),
            ("1 1/2 cup", 80, 2, "3 cups · 160 g"),
            ("1-1/2 cups", 80, 2, "3 cups · 160 g"),
            ("1 piece (1/6 of 16 oz cake)", 70, 2, "2 pieces · 1/6 of 16 oz cake · 140 g"),
            ("1 can, 15 oz (303 x 406)", 425, 2, "2 cans, 15 oz · 303 x 406 · 850 g"),
            ("1 small bagel", 70, 2, "2 small bagels · 140 g"),
            ("1 NLEA serving", 30, 2, "2 NLEA servings · 60 g"),
            ("1 cubic inch", 16, 2, "2 cubic inches · 32 g"),
            ("1 loaf", 400, 2, "2 loaves · 800 g"),
            ("1 medium", 118, 2, "2 medium · 236 g"),
        ]

        for (label, grams, servings, expected) in cases {
            XCTAssertEqual(
                FoodFormatting.servingSummary(
                    Portion(label: label, grams: grams), servings: servings
                ),
                expected,
                label
            )
        }
    }

    func testServingSummaryHandlesFallbacksAndRestatedServing() {
        XCTAssertEqual(FoodFormatting.servingSummary(nil), "100 g")
        XCTAssertEqual(FoodFormatting.servingSummary(nil, servings: 1.5), "150 g")
        XCTAssertEqual(
            FoodFormatting.servingSummary(
                Portion(label: "0.99 oz 1 serving", grams: 28.35), servings: 2
            ),
            "1.98 oz · 57 g"
        )
        XCTAssertEqual(
            FoodFormatting.servingSummary(Portion(label: "(1 slice)", grams: 15)),
            "1 slice · 15 g"
        )
    }

    func testNutrientValuesUseParityPlaceholdersAndRounding() {
        XCTAssertEqual(FoodFormatting.grams(nil), "—")
        XCTAssertEqual(FoodFormatting.grams(20.6), "21g")
        XCTAssertEqual(FoodFormatting.energy(nil), "—")
        XCTAssertEqual(FoodFormatting.energy(20.6), "21")
    }

    func testInvalidNumericValuesUsePlaceholdersInsteadOfTrapping() {
        XCTAssertEqual(FoodFormatting.grams(.infinity), "—")
        XCTAssertEqual(FoodFormatting.energy(.greatestFiniteMagnitude), "—")
        XCTAssertEqual(
            FoodFormatting.servingSummary(
                Portion(label: "1 cup", grams: .greatestFiniteMagnitude), servings: 2
            ),
            "2 cups · — g"
        )
    }

    func testHighInUsesPerHundredGramDailyValueThresholds() {
        let nutrients = Nutrients(
            kcal: nil,
            proteinG: 100,
            fibreG: 5.6,
            vitaminEMg: 2.99,
            magnesiumMg: 84,
            unsaturatedFatG: 100
        )

        XCTAssertEqual(FoodClaims.highIn(nutrients), ["Magnesium", "Fibre"])
        XCTAssertEqual(FoodClaims.highIn(.empty), [])
    }
}
