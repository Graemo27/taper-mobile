import Foundation
import Supabase

struct RecentFood: Decodable, Equatable, Identifiable, Sendable {
    let fdcID: Int
    let name: String
    let servingLabel: String?
    let kcal: Int?
    var id: Int { fdcID }

    enum CodingKeys: String, CodingKey {
        case name, kcal
        case fdcID = "fdc_id"
        case servingLabel = "serving_label"
    }
}

protocol RecentFoodsDataSource: Sendable {
    func fetch(userID: UUID, offset: Int, limit: Int) async throws -> [RecentFood]
}

struct SupabaseRecentFoodsDataSource: RecentFoodsDataSource {
    let client: SupabaseClient

    func fetch(userID: UUID, offset: Int, limit: Int) async throws -> [RecentFood] {
        try await client.from("journal_entries").select("fdc_id,name,serving_label,kcal")
            .eq("user_id", value: userID.uuidString)
            .order("eaten_on", ascending: false).order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1).execute().value
    }
}

struct RecentFoodsRepository: Sendable {
    static let scanLimit = 50
    let sessions: SessionCoordinator
    let source: any RecentFoodsDataSource

    func list(limit: Int = 3) async throws -> [RecentFood] {
        try await sessions.authenticated { userID in
            var offset = 0, result: [RecentFood] = []
            var seen: Set<Int> = []
            while result.count < limit {
                let page = try await source.fetch(userID: userID, offset: offset, limit: Self.scanLimit)
                for food in page where seen.insert(food.fdcID).inserted {
                    result.append(food)
                    if result.count == limit { return result }
                }
                guard page.count == Self.scanLimit else { return result }
                offset += page.count
            }
            return result
        }
    }

    static func newestDistinct(_ rows: [RecentFood], limit: Int) -> [RecentFood] {
        var seen: Set<Int> = []
        return rows.filter { seen.insert($0.fdcID).inserted }.prefix(limit).map { $0 }
    }
}
