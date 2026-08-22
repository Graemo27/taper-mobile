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

    /// The inverse: a stored day, read back as the start of that day where the
    /// user is.
    ///
    /// Deliberately the mirror of `wireFormat` rather than a `DateFormatter` —
    /// same forced Gregorian calendar, same inherited time zone. A parser that
    /// disagreed with the writer by one time zone would put every plan a day
    /// out in exactly the direction nobody would notice.
    ///
    /// Uses the calendar's own validation, so `2025-02-30` is rejected rather
    /// than rolled forward into March.
    ///
    /// Then checks the result round-trips. `split` drops empty pieces, so
    /// `2025--10-09` and `2025-10-09-` both come apart into three usable
    /// numbers — and a parser looser than its writer accepts strings the app
    /// could never have produced. Comparing against `wireFormat` makes the pair
    /// exact by construction rather than by agreement, which matters because
    /// this value arrives from outside the app.
    static func date(from wire: String, calendar base: Calendar = .current) -> Date? {
        let parts = wire.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = base.timeZone
        let components = DateComponents(calendar: calendar, year: year, month: month, day: day)
        guard components.isValidDate,
              let date = calendar.date(from: components),
              wireFormat(date, timeZone: calendar.timeZone) == wire
        else { return nil }
        return date
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
    /// The two dependence answers, kept because the schedule is recomputed from
    /// this row rather than stored beside it. Without them the app can say what
    /// today's cap is and not what the next one will be.
    let firstUseMinutes: Int
    let sickInBed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case startingCapMg = "starting_cap_mg"
        case currentCapMg = "current_cap_mg"
        case capEffectiveFrom = "cap_effective_from"
        case quitDate = "quit_date"
        case firstUseMinutes = "first_use_minutes"
        case sickInBed = "sick_in_bed"
    }
}

/// One version of the plan on the wire.
///
/// The same figures as `TaperPlanRow` under a different date column: the plan
/// calls it `cap_effective_from` because it is when today's cap was pinned, and
/// a version calls it `effective_from` because it is when this whole version
/// took over. Written out by hand for the reason the plan row is — two shapes
/// agreeing today is not a reason to let one rename rewrite the other.
private struct TaperPlanVersionRow: Encodable {
    let userID: UUID
    let effectiveFrom: String
    let startingCapMg: Double
    let currentCapMg: Double
    let quitDate: String?
    let firstUseMinutes: Int
    let sickInBed: Bool

    init(draft: TaperPlanDraft, userID: UUID, timeZone: TimeZone) {
        self.userID = userID
        effectiveFrom = PlanDay.wireFormat(draft.capEffectiveFrom, timeZone: timeZone)
        startingCapMg = draft.startingCapMg
        currentCapMg = draft.currentCapMg
        quitDate = draft.quitDate.map { PlanDay.wireFormat($0, timeZone: timeZone) }
        firstUseMinutes = draft.firstUseMinutes
        sickInBed = draft.sickInBed
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case effectiveFrom = "effective_from"
        case startingCapMg = "starting_cap_mg"
        case currentCapMg = "current_cap_mg"
        case quitDate = "quit_date"
        case firstUseMinutes = "first_use_minutes"
        case sickInBed = "sick_in_bed"
    }
}

/// Writing the plan, as a protocol so the screen that calls it can be driven
/// without a backend.
protocol TaperPlanWriting: Sendable {
    func save(_ draft: TaperPlanDraft) async throws -> StoredTaperPlan
}

/// Reading the plan already on file.
///
/// Separate from writing because the callers are different: the write happens
/// once, at the end of a run someone just completed, and the read happens at
/// every launch before anything is shown. A type that only writes is a type
/// that cannot tell a returning user from a new one — which is the app as
/// shipped today, replaying twelve questions at somebody whose plan is already
/// on the server.
protocol TaperPlanReading: Sendable {
    /// The signed-in user's plan, or nil when they have none.
    ///
    /// Nil means *they have no plan*, never *we could not find out*. A read
    /// that fails throws, because the two must not arrive at the caller
    /// wearing the same face — one of them is a reason to run onboarding and
    /// the other is a reason to say the app could not check.
    func currentPlan() async throws -> StoredTaperPlan?
}

/// Reading the plan's history.
///
/// Separate from `TaperPlanReading` rather than folded into it: the screens
/// that ask "what is my plan" and "what was my plan in August" are different
/// screens, and the record that draws today has no business being able to ask
/// the second question.
protocol PlanVersionReading: Sendable {
    /// Every version this user has, newest first.
    func versions() async throws -> [StoredPlanVersion]
}

/// Both halves, for the one caller that needs each. Named rather than written
/// as `TaperPlanWriting & TaperPlanReading` at every use site, because the
/// composition is the thing the app actually depends on.
typealias TaperPlanStoring = TaperPlanWriting & TaperPlanReading

/// Saves and reads the plan, and its history, through Supabase as the
/// signed-in anonymous user.
///
/// Upserts rather than inserts. `taper_plans` holds one row per person by
/// unique index, and re-running onboarding is not an error state — it is what
/// happens every time someone reopens the app today, because nothing yet
/// records that the run was completed. An insert would fail on the second run
/// with a constraint violation the user has no way to read.
struct SupabaseTaperPlanStore: TaperPlanWriting, TaperPlanReading {
    let client: SupabaseClient
    let session: SessionCoordinator
    /// The zone the user's day is read in. `.current` in the app, and fixed in
    /// the live test — on a UTC runner there is no local time whose day differs
    /// from UTC's, so a test that cannot choose the zone cannot prove the day
    /// survived the trip.
    var timeZone: TimeZone = .current

    func save(_ draft: TaperPlanDraft) async throws -> StoredTaperPlan {
        try await session.authenticated { userID in
            // The version first, then the plan, because that order recovers.
            //
            // `taper_plans` is one upserted row: saving replaces what was there
            // and the previous cap is gone. The version is the copy a past day
            // is measured against, so writing it second would mean a crash
            // between the two left a plan whose earlier days have no ceiling to
            // draw against — unrecoverable, because the number needed to write
            // the version has just been overwritten.
            //
            // The other way round is recoverable: a version with no plan yet is
            // corrected by the retry, and the unique constraint on
            // (user_id, effective_from) makes writing it twice a no-op. Same
            // reasoning as the pad and the plan in `PlanRecord.submit`.
            try await client
                .from("taper_plan_versions")
                .upsert(
                    TaperPlanVersionRow(draft: draft, userID: userID, timeZone: timeZone),
                    onConflict: "user_id,effective_from"
                )
                .execute()

            return try await client
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

/// One version as the table holds it, for the tests and for the reader that
/// will draw past days against it.
///
/// **Every input the planner reads, or the version is worthless.** The schedule
/// is recomputed rather than stored, so a reader missing one of these fields has
/// to borrow it from the current plan — and a past day recomputed with today's
/// dependence answers is exactly the restatement this table exists to prevent.
/// The same fields, for the same reason, as the ones `StoredTaperPlan` keeps.
struct StoredPlanVersion: Decodable, Equatable, Sendable {
    let effectiveFrom: String
    let startingCapMg: Double
    let currentCapMg: Double
    let quitDate: String?
    let firstUseMinutes: Int
    let sickInBed: Bool

    enum CodingKeys: String, CodingKey {
        case effectiveFrom = "effective_from"
        case startingCapMg = "starting_cap_mg"
        case currentCapMg = "current_cap_mg"
        case quitDate = "quit_date"
        case firstUseMinutes = "first_use_minutes"
        case sickInBed = "sick_in_bed"
    }
}

extension SupabaseTaperPlanStore: PlanVersionReading {
    /// Every version this user has, newest first.
    ///
    /// The order the reader wants: a past day's plan is the first version at or
    /// before it, which is a scan that stops at the first row.
    func versions() async throws -> [StoredPlanVersion] {
        try await session.authenticated { userID in
            try await client
                .from("taper_plan_versions")
                .select("""
                    effective_from,starting_cap_mg,current_cap_mg,quit_date,\
                    first_use_minutes,sick_in_bed
                    """)
                .eq("user_id", value: userID)
                .order("effective_from", ascending: false)
                .execute()
                .value
        }
    }

    func currentPlan() async throws -> StoredTaperPlan? {
        try await session.authenticated { userID in
            // Filtered by user_id as well as trusting RLS. The policy is the
            // thing that enforces it, but a query with no predicate asks the
            // database for every plan and relies on the filter to be correct —
            // and a read that is only safe because of a policy is one that
            // breaks silently if the policy is ever loosened.
            try await client
                .from("taper_plans")
                .select()
                .eq("user_id", value: userID)
                // A list of at most one, rather than `single`. Having no plan
                // is the ordinary answer for anyone who has not finished
                // onboarding, and `single` raises on an empty result — which
                // would reach the caller as an error indistinguishable from a
                // read that genuinely failed. Taking `.first` of a list makes
                // "none" a value instead.
                .limit(1)
                .execute()
                .value as [StoredTaperPlan]
        }.first
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
