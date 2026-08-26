import Foundation
import Supabase

/// The daily check-in's three words: how cravings were, said once per day.
///
/// A closed vocabulary because the card is three chips, and because the
/// database holds the same three words as a check constraint — a fourth case
/// here without a migration there would be a rating the server refuses.
enum DayRating: String, CaseIterable, Codable, Sendable {
    case easy
    case soSo = "so_so"
    case rough
}

/// Reads and writes the day's rating.
///
/// One judgement per day, so the write is an upsert: a changed mind lands on
/// the same row, and clearing takes the answer back — "skip freely" has to
/// include un-answering.
protocol DayRatingStoring: Sendable {
    func rating(on day: Date) async throws -> DayRating?
    func rate(_ rating: DayRating, on day: Date) async throws
    func clearRating(on day: Date) async throws
}

/// The store over `craving_ratings`, as the signed-in anonymous user.
struct SupabaseDayRatingStore: DayRatingStoring {
    let client: SupabaseClient
    let session: SessionCoordinator
    /// Fixed in tests, for the reason every store fixes it: on a UTC runner no
    /// local time disagrees with UTC, so a wrongly serialized day round-trips.
    var timeZone: TimeZone = .current

    func rating(on day: Date) async throws -> DayRating? {
        try await session.authenticated { userID in
            let rows: [RatingRow] = try await client
                .from("craving_ratings")
                .select("rating")
                // Filtered as well as trusting RLS, for the reason every read
                // gives: a query that is only safe because of a policy breaks
                // silently the day the policy is loosened.
                .eq("user_id", value: userID)
                .eq("logged_on", value: PlanDay.wireFormat(day, timeZone: timeZone))
                .execute()
                .value
            return rows.first?.rating
        }
    }

    func rate(_ rating: DayRating, on day: Date) async throws {
        try await session.authenticated { userID in
            _ = try await client
                .from("craving_ratings")
                .upsert(
                    RatingWrite(
                        userID: userID,
                        loggedOn: PlanDay.wireFormat(day, timeZone: timeZone),
                        rating: rating
                    ),
                    // The table's unique constraint, named so the conflict
                    // lands there and becomes the update it is meant to be.
                    onConflict: "user_id,logged_on"
                )
                .execute()
                .status
        }
    }

    func clearRating(on day: Date) async throws {
        try await session.authenticated { userID in
            _ = try await client
                .from("craving_ratings")
                .delete()
                .eq("user_id", value: userID)
                .eq("logged_on", value: PlanDay.wireFormat(day, timeZone: timeZone))
                .execute()
                .status
        }
    }

    private struct RatingRow: Decodable {
        let rating: DayRating
    }

    private struct RatingWrite: Encodable {
        let userID: UUID
        let loggedOn: String
        let rating: DayRating

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case loggedOn = "logged_on"
            case rating
        }
    }
}
