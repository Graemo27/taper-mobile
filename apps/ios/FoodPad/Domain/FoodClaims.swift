/// The "High in" chip thresholds, ported case for case from `claims.ts`.
enum FoodClaims {
    private struct Claim {
        let label: String
        let value: KeyPath<Nutrients, Double?>
        let threshold: Double
    }

    /// Describes density per 100 g; it is not an FDA nutrient-content claim.
    static func highIn(_ per100g: Nutrients) -> [String] {
        let claims = [
            Claim(label: "Vitamin E", value: \.vitaminEMg, threshold: 3),
            Claim(label: "Magnesium", value: \.magnesiumMg, threshold: 84),
            Claim(label: "Fibre", value: \.fibreG, threshold: 5.6),
        ]
        return claims.compactMap { claim -> String? in
            guard let amount = per100g[keyPath: claim.value],
                  amount >= claim.threshold else { return nil }
            return claim.label
        }
    }
}
