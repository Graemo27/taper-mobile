import Foundation
import Supabase

/// A calendar day, in the form the schema stores it.
///
/// `cap_effective_from` and `quit_date` are `date` columns, not timestamps, and
/// the difference is the whole of this type. Handing Postgres an instant makes
/// it pick a day, and the day it picks is UTC's — so a plan confirmed at 9pm in
/// California starts tomorrow, and a quit date chosen on the 14th is stored as
/// the 15th. The user is never told, and every countdown afterwards is a day
/// out.
enum PlanDay {
    /// The day this instant falls on where the user is.
    ///
    /// Gregorian is forced rather than inherited. `Calendar.current` follows the
    /// device, and a device set to the Buddhist calendar reports 2569 for this
    /// year — a value the column rejects, on a setting nobody testing in London
    /// or California will have switched on. This project has already shipped
    /// that exact bug once.
    ///
    /// The time zone is *not* forced, because that half has to follow the
    /// device: the whole point is the user's own day.
    static func wireFormat(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The plan as `taper_plans` holds it, once written.
///
/// The dates come back as the strings the column stores rather than as `Date`s.
/// Decoding them into instants would re-introduce the timezone question this
/// file exists to answer, and the caller that wants a day has one already.
struct StoredTaperPlan: Decodable, Equatable, Sendable {
    let id: Int
    let startingCapMg: Double
    let currentCapMg: Double
    let capEffectiveFrom: String
    let quitDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startingCapMg = "starting_cap_mg"
        case currentCapMg = "current_cap_mg"
        case capEffectiveFrom = "cap_effective_from"
        case quitDate = "quit_date"
    }
}

/// Writing the plan, as a protocol so the screen that calls it can be driven
/// without a backend.
protocol TaperPlanWriting: Sendable {
    func save(_ draft: TaperPlanDraft) async throws -> StoredTaperPlan
}

/// The real one.
///
/// Upserts rather than inserts. `taper_plans` holds one row per person by
/// unique index, and re-running onboarding is not an error state — it is what
/// happens every time someone reopens the app today, because nothing yet
/// records that the run was completed. An insert would fail on the second run
/// with a constraint violation the user has no way to read.
struct SupabaseTaperPlanStore: TaperPlanWriting {
    let client: SupabaseClient
    let session: SessionCoordinator
    /// The zone the user's day is read in. `.current` in the app, and fixed in
    /// the live test — on a UTC runner there is no local time whose day differs
    /// from UTC's, so a test that cannot choose the zone cannot prove the day
    /// survived the trip.
    var timeZone: TimeZone = .current

    func save(_ draft: TaperPlanDraft) async throws -> StoredTaperPlan {
        try await session.authenticated { userID in
            try await client
                .from("taper_plans")
                .upsert(
                    TaperPlanRow(draft: draft, userID: userID, timeZone: timeZone),
                    onConflict: "user_id"
                )
                .select()
                .single()
                .execute()
                .value
        }
    }
}

/// The row on the wire.
///
/// Written out by hand rather than derived from `TaperPlanDraft`. The draft is
/// the app's shape and this is the table's, and the two agreeing today is not a
/// reason to let one rename silently rewrite the other.
private struct TaperPlanRow: Encodable {
    let userID: UUID
    let startingCapMg: Double
    let currentCapMg: Double
    let capEffectiveFrom: String
    let quitDate: String?
    let firstUseMinutes: Int
    let sickInBed: Bool

    init(draft: TaperPlanDraft, userID: UUID, timeZone: TimeZone) {
        self.userID = userID
        startingCapMg = draft.startingCapMg
        currentCapMg = draft.currentCapMg
        capEffectiveFrom = PlanDay.wireFormat(draft.capEffectiveFrom, timeZone: timeZone)
        quitDate = draft.quitDate.map { PlanDay.wireFormat($0, timeZone: timeZone) }
        firstUseMinutes = draft.firstUseMinutes
        sickInBed = draft.sickInBed
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case startingCapMg = "starting_cap_mg"
        case currentCapMg = "current_cap_mg"
        case capEffectiveFrom = "cap_effective_from"
        case quitDate = "quit_date"
        case firstUseMinutes = "first_use_minutes"
        case sickInBed = "sick_in_bed"
    }
}
