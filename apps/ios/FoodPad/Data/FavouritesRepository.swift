import Foundation
import Supabase

/// A user's favourites as a set of FDC ids.
protocol FavouritesDataSource: Sendable {
    func list(userID: UUID) async throws -> Set<Int>
    func add(userID: UUID, fdcID: Int) async throws
    func remove(userID: UUID, fdcID: Int) async throws
}

/// PostgREST rows keyed (user, fdc id); `add` upserts so repeating a
/// favourite is not an error.
struct SupabaseFavouritesDataSource: FavouritesDataSource {
    let client: SupabaseClient

    func list(userID: UUID) async throws -> Set<Int> {
        let rows: [Row] = try await client.from("favourites").select("fdc_id")
            .eq("user_id", value: userID.uuidString).execute().value
        return Set(rows.map(\.fdcID))
    }

    func add(userID: UUID, fdcID: Int) async throws {
        try await client.from("favourites")
            .upsert(Row(userID: userID, fdcID: fdcID), onConflict: "user_id,fdc_id", ignoreDuplicates: true)
            .execute()
    }

    func remove(userID: UUID, fdcID: Int) async throws {
        try await client.from("favourites").delete()
            .eq("user_id", value: userID.uuidString).eq("fdc_id", value: fdcID).execute()
    }

    private struct Row: Codable {
        var userID: UUID?
        let fdcID: Int
        enum CodingKeys: String, CodingKey { case userID = "user_id"; case fdcID = "fdc_id" }
        init(userID: UUID? = nil, fdcID: Int) { self.userID = userID; self.fdcID = fdcID }
    }
}

/// Reads and toggles favourites as the current user.
struct FavouritesRepository: Sendable {
    let sessions: SessionCoordinator
    let source: any FavouritesDataSource

    func list() async throws -> Set<Int> {
        try await sessions.authenticated { try await source.list(userID: $0) }
    }

    func set(_ on: Bool, fdcID: Int) async throws {
        try await sessions.authenticated { userID in
            if on { try await source.add(userID: userID, fdcID: fdcID) }
            else { try await source.remove(userID: userID, fdcID: fdcID) }
        }
    }
}
