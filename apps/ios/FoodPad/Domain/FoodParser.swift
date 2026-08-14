import Foundation

enum FoodParser {
    /// Normalizes the flat search and nested detail nutrient shapes FDC returns.
    static func nutrients(from data: Data) throws -> Nutrients {
        let nutrients = try JSONDecoder().decode([RawNutrient].self, from: data)
        let kcal = find(nutrients, named: "Energy", unit: "kcal")
        let mono = find(nutrients, named: "Fatty acids, total monounsaturated", unit: "g")
        let poly = find(nutrients, named: "Fatty acids, total polyunsaturated", unit: "g")

        return Nutrients(
            kcal: kcal.map { Int($0.rounded()) },
            proteinG: rounded(find(nutrients, named: "Protein", unit: "g")),
            fibreG: rounded(find(nutrients, named: "Fiber, total dietary", unit: "g")),
            vitaminEMg: rounded(
                find(nutrients, named: "Vitamin E (alpha-tocopherol)", unit: "mg")
            ),
            magnesiumMg: rounded(find(nutrients, named: "Magnesium, Mg", unit: "mg")),
            // Both halves or nothing: publishing one half would present a lower bound as a total.
            unsaturatedFatG: mono.flatMap { mono in poly.map { rounded(mono + $0) } }
        )
    }

    static func portions(from data: Data) throws -> [Portion] {
        try JSONDecoder().decode([RawPortion].self, from: data).compactMap { raw in
            guard let grams = raw.gramWeight, grams > 0 else { return nil }

            // FDC has real positive-weight portions whose recorded amount is zero.
            let amount = raw.amount.flatMap { $0 > 0 ? $0 : nil } ?? 1
            let unit = raw.measureUnit?.name ?? ""
            let modifier = withoutJargon(raw.modifier?.trimmingCharacters(in: .whitespaces) ?? "")
            // RACC names a reference serving, while "undetermined" supplies no noun at all.
            let isRACC = unit.uppercased() == "RACC"
            let isNamed = !unit.isEmpty && unit != "undetermined" && !isRACC
            let noun = isNamed ? unit : isRACC ? "serving" : modifier.isEmpty ? "serving" : modifier
            let qualifier = (isNamed || isRACC) && !modifier.isEmpty ? " (\(modifier))" : ""

            return Portion(label: "\(number(amount)) \(noun)\(qualifier)", grams: grams)
        }
    }

    static func pickPortion(from portions: [Portion]) -> Portion? {
        func first(from lower: Double, through upper: Double) -> Portion? {
            portions.first { $0.grams >= lower && $0.grams <= upper }
        }

        // Prefer a plausible eating quantity without reordering FDC's choices.
        return first(from: 20, through: 150)
            ?? first(from: 10, through: 300)
            ?? portions.first
    }

    static func scale(_ nutrients: Nutrients, toGrams grams: Double) -> Nutrients {
        let factor = grams / 100
        func scaled(_ value: Double?) -> Double? {
            value.map { rounded($0 * factor) }
        }

        return Nutrients(
            kcal: nutrients.kcal.map { Int((Double($0) * factor).rounded()) },
            proteinG: scaled(nutrients.proteinG),
            fibreG: scaled(nutrients.fibreG),
            vitaminEMg: scaled(nutrients.vitaminEMg),
            magnesiumMg: scaled(nutrients.magnesiumMg),
            unsaturatedFatG: scaled(nutrients.unsaturatedFatG)
        )
    }

    private static func find(
        _ nutrients: [RawNutrient],
        named name: String,
        unit: String
    ) -> Double? {
        nutrients.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
                && $0.unit.compare(unit, options: .caseInsensitive) == .orderedSame
        }?.reading
    }

    private static func rounded(_ value: Double?) -> Double? {
        value.map { ($0 * 10).rounded() / 10 }
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func withoutJargon(_ modifier: String) -> String {
        // Removing an NLEA phrase can leave an empty parenthetical or dangling separator.
        [
            (#"(?i)\d+(?:\.\d+)?\s*NLEA\s+servings?"#, ""),
            (#"\(\s*[-–—,;]*\s*"#, "("),
            (#"\s*[-–—,;]*\s*\)"#, ")"),
            (#"\(\s*\)"#, ""),
            (#"\s{2,}"#, " "),
            (#"^[\s\-–—,;]+"#, ""),
            (#"[\s\-–—,;]+$"#, ""),
        ].reduce(modifier) { value, replacement in
            value.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .regularExpression
            )
        }.trimmingCharacters(in: .whitespaces)
    }
}

private struct RawNutrient: Decodable {
    struct Descriptor: Decodable {
        let name: String?
        let unitName: String?
    }

    let nutrientName: String?
    let unitName: String?
    let value: Double?
    let amount: Double?
    let nutrient: Descriptor?

    var name: String { nutrient?.name ?? nutrientName ?? "" }
    var unit: String { nutrient?.unitName ?? unitName ?? "" }
    var reading: Double? { amount ?? value }
}

private struct RawPortion: Decodable {
    struct MeasureUnit: Decodable { let name: String? }

    let amount: Double?
    let gramWeight: Double?
    let measureUnit: MeasureUnit?
    let modifier: String?
}
