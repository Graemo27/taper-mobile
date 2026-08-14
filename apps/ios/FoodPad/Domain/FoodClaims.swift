enum FoodClaims {
    private struct Claim {
        let label: String
        let value: KeyPath<Nutrients, Double?>
        let dailyValue: Double
    }

    /// Describes density per 100 g; it is not an FDA nutrient-content claim.
    static func highIn(_ per100g: Nutrients) -> [String] {
        let claims = [
            Claim(label: "Vitamin E", value: \.vitaminEMg, dailyValue: 15),
            Claim(label: "Magnesium", value: \.magnesiumMg, dailyValue: 420),
            Claim(label: "Fibre", value: \.fibreG, dailyValue: 28),
        ]
        return claims.compactMap { claim -> String? in
            guard let amount = per100g[keyPath: claim.value],
                  amount >= claim.dailyValue * 0.2 else { return nil }
            return claim.label
        }
    }
}
