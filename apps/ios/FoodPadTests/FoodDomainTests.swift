import XCTest
@testable import FoodPad

final class FoodDomainTests: XCTestCase {
    func testNutrientsAcceptBothFDCShapesAndDistinguishEnergyUnits() throws {
        let data = Data(#"""
        [
          {"nutrientName":"Energy","unitName":"kJ","value":840},
          {"nutrientName":"Energy","unitName":"kcal","value":201.6},
          {"nutrientName":"Protein","unitName":"g","value":20.78734},
          {"nutrient":{"name":"Fiber, total dietary","unitName":"g"},"amount":3.26},
          {"nutrient":{"name":"Vitamin E (alpha-tocopherol)","unitName":"mg"},"amount":2.04},
          {"nutrientName":"Magnesium, Mg","unitName":"mg","value":84.06},
          {"nutrientName":"Fatty acids, total monounsaturated","unitName":"g","value":4.04},
          {"nutrientName":"Fatty acids, total polyunsaturated","unitName":"g","value":1.02}
        ]
        """#.utf8)

        XCTAssertEqual(
            try FoodParser.nutrients(from: data),
            Nutrients(
                kcal: 202, proteinG: 20.8, fibreG: 3.3, vitaminEMg: 2,
                magnesiumMg: 84.1, unsaturatedFatG: 5.1
            )
        )
    }

    func testNutrientsKeepMissingAndIncompleteValuesNil() throws {
        let data = Data(#"""
        [
          {"nutrientName":"Fatty acids, total monounsaturated","unitName":"g","value":4},
          {"nutrientName":"Vitamin E","unitName":"mg","value":9}
        ]
        """#.utf8)

        XCTAssertEqual(try FoodParser.nutrients(from: data), .empty)
    }

    func testPortionsCleanJargonAndDiscardInvalidWeights() throws {
        let data = Data(#"""
        [
          {"amount":1,"gramWeight":30,"measureUnit":{"name":"cup"},"modifier":"1 NLEA serving - about 4 crackers"},
          {"amount":1,"gramWeight":40,"measureUnit":{"name":"RACC"},"modifier":"about 4 crackers"},
          {"amount":0,"gramWeight":113,"measureUnit":{"name":"undetermined"},"modifier":"container (4 oz)"},
          {"amount":1,"gramWeight":0,"measureUnit":{"name":"slice"}}
        ]
        """#.utf8)

        XCTAssertEqual(
            try FoodParser.portions(from: data),
            [
                Portion(label: "1 cup (about 4 crackers)", grams: 30),
                Portion(label: "1 serving (about 4 crackers)", grams: 40),
                Portion(label: "1 container (4 oz)", grams: 113),
            ]
        )
    }

    func testPortionSelectionPrefersPlausibleEatingQuantity() {
        let portions = [
            Portion(label: "1 almond", grams: 1.2),
            Portion(label: "1 cup", grams: 143),
            Portion(label: "1 bag", grams: 400),
        ]

        XCTAssertEqual(FoodParser.pickPortion(from: portions), portions[1])
        XCTAssertNil(FoodParser.pickPortion(from: []))
    }

    func testScalingRoundsOnceAndPreservesMissingValues() {
        let nutrients = Nutrients(
            kcal: 201, proteinG: 20.78, fibreG: nil, vitaminEMg: 2,
            magnesiumMg: 84, unsaturatedFatG: 5.05
        )

        XCTAssertEqual(
            FoodParser.scale(nutrients, toGrams: 28.35),
            Nutrients(
                kcal: 57, proteinG: 5.9, fibreG: nil, vitaminEMg: 0.6,
                magnesiumMg: 23.8, unsaturatedFatG: 1.4
            )
        )
    }
}
