import Foundation

enum FoodFormatting {
    private struct Quantity {
        let value: Double
        let rest: String
    }

    private static let uncounted: Set<String> = [
        "cal", "cm", "fl", "g", "gal", "in", "kcal", "kg", "l", "lb", "mg", "ml",
        "mm", "oz", "pt", "qt", "tbsp", "tsp",
        // FDC uses sizes as standalone portions: two bananas are "2 medium".
        "extra", "cubic", "each", "jumbo", "large", "medium", "mini", "regular", "small",
        "thick", "thin",
    ]

    private static let irregular = [
        "half": "halves",
        "leaf": "leaves",
        "loaf": "loaves",
        "mango": "mangoes",
        "potato": "potatoes",
        "tomato": "tomatoes",
    ]

    static func servingSummary(_ portion: Portion?, servings: Double = 1) -> String {
        guard let portion else { return "\(number(100 * servings)) g" }

        let label = portion.label.replacingOccurrences(
            of: #"\s+\d+(?:\.\d+)?\s+servings?$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let groups = match(#"^(.*?)\s*\((.*)\)\s*$"#, in: label)?.groups
        let parts = (groups ?? [label]).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let summary = parts.map { scaleSegment($0, servings: servings) }
        return (summary + ["\(Int((portion.grams * servings).rounded())) g"]).joined(separator: " · ")
    }

    static func grams(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))g" } ?? "—"
    }

    static func energy(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "—"
    }

    private static func leadingQuantity(_ text: String) -> Quantity? {
        if let parsed = match(#"^(\d+)\s+(\d+)/(\d+)\s*"#, in: text) {
            guard let whole = Double(parsed.groups[0]),
                  let numerator = Double(parsed.groups[1]),
                  let denominator = Double(parsed.groups[2]),
                  denominator != 0 else { return nil }
            return Quantity(
                value: whole + numerator / denominator,
                rest: String(text[parsed.range.upperBound...])
            )
        }
        if let parsed = match(#"^(\d+)/(\d+)\s*"#, in: text) {
            guard let numerator = Double(parsed.groups[0]),
                  let denominator = Double(parsed.groups[1]),
                  denominator != 0 else { return nil }
            return Quantity(
                value: numerator / denominator,
                rest: String(text[parsed.range.upperBound...])
            )
        }
        guard let parsed = match(#"^(\d+(?:\.\d+)?)\s*"#, in: text),
              let value = Double(parsed.groups[0]) else { return nil }
        return Quantity(
            value: value,
            rest: String(text[parsed.range.upperBound...])
        )
    }

    private static func scaleSegment(_ segment: String, servings: Double) -> String {
        guard servings != 1 else { return segment }
        guard let quantity = leadingQuantity(segment.trimmingCharacters(in: .whitespaces)) else {
            return segment
        }

        // Ranges, dimensions, shares, and can-size codes describe rather than count the food.
        if quantity.rest.contains(where: { "\"'-/".contains($0) })
            || quantity.rest.range(of: #"^of\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || quantity.rest.range(of: #"^x\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return segment
        }

        let scaled = (quantity.value * servings * 100).rounded() / 100
        guard !quantity.rest.isEmpty else { return number(scaled) }
        return "\(number(scaled)) \(scaled == 1 ? quantity.rest : pluralised(quantity.rest))"
    }

    private static func pluralised(_ rest: String) -> String {
        var words = rest.components(separatedBy: " ")
        let index = words.first.map(precedesNoun) == true ? 1 : 0
        guard words.indices.contains(index),
              let parsed = match(#"^([A-Za-z]+)(\W*)$"#, in: words[index]) else { return rest }

        let word = parsed.groups[0]
        let lower = word.lowercased()
        guard !precedesNoun(word), !lower.hasSuffix("s") else { return rest }

        let suffixed = plural(lower)
        let cased = word.first?.isUppercase == true
            ? suffixed.prefix(1).uppercased() + String(suffixed.dropFirst())
            : suffixed
        words[index] = cased + parsed.groups[1]
        return words.joined(separator: " ")
    }

    private static func precedesNoun(_ word: String) -> Bool {
        let bare = word.replacingOccurrences(
            of: #"\W+$"#, with: "", options: .regularExpression
        )
        return uncounted.contains(bare.lowercased())
            || (bare.count > 1 && bare == bare.uppercased())
    }

    private static func plural(_ word: String) -> String {
        if let known = irregular[word] { return known }
        if word.range(of: #"(x|z|ch|sh)$"#, options: .regularExpression) != nil {
            return word + "es"
        }
        if word.range(of: #"[^aeiou]y$"#, options: .regularExpression) != nil {
            return String(word.dropLast()) + "ies"
        }
        return word + "s"
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func match(
        _ pattern: String,
        in text: String
    ) -> (range: Range<String.Index>, groups: [String])? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(
                  in: text, range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(result.range, in: text) else { return nil }

        var groups: [String] = []
        for index in 1..<result.numberOfRanges {
            guard let group = Range(result.range(at: index), in: text) else { return nil }
            groups.append(String(text[group]))
        }
        return (range, groups)
    }
}
