import Foundation
import Supabase

/// A journal row reduced to what the Recent card shows, identified by food
/// rather than by entry so one food appears once.
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

/// Newest journal rows for a user, in a total order.
protocol RecentFoodsDataSource: Sendable {
    func fetch(userID: UUID, limit: Int) async throws -> [RecentFood]
}

/// Orders by eaten date, then created-at, then id — the tie-breaker that
/// makes paging by widening prefix sound.
struct SupabaseRecentFoodsDataSource: RecentFoodsDataSource {
    let client: SupabaseClient

    func fetch(userID: UUID, limit: Int) async throws -> [RecentFood] {
        try await client.from("journal_entries").select("fdc_id,name,serving_label,kcal")
            .eq("user_id", value: userID.uuidString)
            .order("eaten_on", ascending: false).order("created_at", ascending: false)
            .order("id", ascending: false).limit(limit).execute().value
    }
}

/// The three newest distinct foods, deduplicating after ordering and widening
/// the read until it has enough or the rows run out.
struct RecentFoodsRepository: Sendable {
    static let scanLimit = 50
    let sessions: SessionCoordinator
    let source: any RecentFoodsDataSource

    func list(limit: Int = 3) async throws -> [RecentFood] {
        try await sessions.authenticated { userID in
            var readLimit = Self.scanLimit
            while true {
                // Re-reading one widening, totally ordered prefix avoids offset drift when rows change.
                let rows = try await source.fetch(userID: userID, limit: readLimit)
                let result = Self.newestDistinct(rows, limit: limit)
                if result.count == limit || rows.count < readLimit { return result }
                readLimit += Self.scanLimit
            }
        }
    }

    static func newestDistinct(_ rows: [RecentFood], limit: Int) -> [RecentFood] {
        var seen: Set<Int> = []
        return rows.filter { seen.insert($0.fdcID).inserted }.prefix(limit).map { $0 }
    }
}
