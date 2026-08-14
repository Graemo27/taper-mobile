import Foundation

/// A household measure whose label is shown verbatim in the food UI.
struct Portion: Codable, Equatable, Sendable {
    let label: String
    let grams: Double
}

/// The six values this product tracks, all optional because FDC omits freely.
struct Nutrients: Codable, Equatable, Sendable {
    let kcal: Int?
    let proteinG: Double?
    let fibreG: Double?
    let vitaminEMg: Double?
    let magnesiumMg: Double?
    let unsaturatedFatG: Double?

    /// Missing FDC readings stay absent; a gap must never become a displayed zero.
    static let empty = Nutrients(
        kcal: nil,
        proteinG: nil,
        fibreG: nil,
        vitaminEMg: nil,
        magnesiumMg: nil,
        unsaturatedFatG: nil
    )
}

/// A search result row before its detail is fetched.
struct FoodHit: Codable, Equatable, Identifiable, Sendable {
    let fdcId: Int
    let name: String
    let category: String?
    let dataType: String

    var id: Int { fdcId }
}

/// A fully resolved food: per-100g always, per-serving when FDC lists a
/// usable household portion.
struct Food: Codable, Equatable, Identifiable, Sendable {
    let fdcId: Int
    let name: String
    let category: String?
    let dataType: String
    let portion: Portion?
    let per100g: Nutrients
    let perServing: Nutrients?
    let portions: [Portion]

    var id: Int { fdcId }
}
