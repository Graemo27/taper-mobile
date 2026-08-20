import Foundation
import Supabase
import Testing
@testable import Taper

/// Covers the day the plan is stored against.
///
/// The whole suite is about one column type. `cap_effective_from` and
/// `quit_date` are `date`, and every way of turning an instant into a date is a
/// chance to store a different day from the one the user saw.
struct PlanDayTests {
    /// 2026-08-19, 23:30 in Los Angeles — which is already the 20th in UTC.
    private var lateEvening: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 19
        components.hour = 23
        components.minute = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: components)!
    }

    @Test("the day stored is the user's day, not UTC's")
    func lateEveningDoesNotRollForward() {
        // The defect this guards is silent and permanent: a plan confirmed at
        // 9pm starts tomorrow, a quit date chosen on the 14th is stored as the
        // 15th, and every countdown afterwards is a day out.
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        #expect(PlanDay.wireFormat(lateEvening, timeZone: losAngeles) == "2026-08-19")
        // Same instant, read in UTC, genuinely is the next day — so the
        // assertion above is discriminating rather than incidental.
        #expect(PlanDay.wireFormat(lateEvening, timeZone: TimeZone(identifier: "UTC")!) == "2026-08-20")
    }

    @Test("a day just after midnight belongs to the day that started")
    func earlyMorningStaysPut() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 0
        components.minute = 15
        var calendar = Calendar(identifier: .gregorian)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        calendar.timeZone = tokyo
        #expect(PlanDay.wireFormat(calendar.date(from: components)!, timeZone: tokyo) == "2026-01-01")
    }

    @Test("the year written is Gregorian, whatever the device counts in")
    func theEraIsNotTheDevices() {
        // This project has shipped a Buddhist year once already. A device set
        // that way reports 2569 for 2026, which the column rejects — on a
        // setting nobody testing in London or California has switched on.
        #expect(PlanDay.wireFormat(lateEvening, timeZone: TimeZone(identifier: "UTC")!).hasPrefix("2026-"))
    }

    @Test("single-digit months and days are padded, because the column is fixed width")
    func partsArePadded() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        calendar.timeZone = utc
        #expect(PlanDay.wireFormat(calendar.date(from: components)!, timeZone: utc) == "2026-03-07")
    }
}

/// Where the live round-trip points, and whether it may run at all.
///
/// Loopback only, and that is a safety control rather than convenience.
/// `taper_plans` has no delete policy by design — nothing in the product
/// removes a plan — so this test writes a row it has no way to take back.
/// Against the hosted project that would leave a plan on a real anonymous
/// account permanently. A local stack is thrown away by `supabase db reset`.
private enum LocalBackend {
    static var url: URL? {
        ProcessInfo.processInfo.environment["TAPER_TEST_SUPABASE_URL"].flatMap(URL.init(string:))
    }

    static var key: String? {
        ProcessInfo.processInfo.environment["TAPER_TEST_SUPABASE_KEY"]
    }

    static var isLoopback: Bool {
        ["127.0.0.1", "localhost", "::1"].contains(url?.host() ?? "")
    }

    static var isAvailable: Bool { url != nil && key != nil && isLoopback }
}

/// Drives the store against a real Postgres with the real migrations applied.
///
/// Skipped unless a loopback backend is configured, and the skip is visible in
/// the run rather than silent. The reason it is worth having at all is that the
/// column names, the date format and the row-level security policy are all
/// things a mock would agree with and a database would not: a store that writes
/// `quit_date` as a timestamp, or spells a column wrong, passes every test that
/// does not talk to Postgres.
///
/// Run it with:
///
///   supabase start && supabase db reset --local
///   TAPER_TEST_SUPABASE_URL=http://127.0.0.1:55321 \
///   TAPER_TEST_SUPABASE_KEY=<local publishable key from `supabase status`> \
///   xcodebuild test ... -only-testing:TaperTests/TaperPlanStoreLiveTests
struct TaperPlanStoreLiveTests {
    /// Fixed, and deliberately not the runner's.
    ///
    /// On a UTC runner there is no local time whose day differs from UTC's, so
    /// a serialization regression round-trips perfectly and the assertions
    /// below prove nothing. Pinning the zone is what makes them discriminate
    /// everywhere rather than only on a machine west of Greenwich.
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    private func store() async -> SupabaseTaperPlanStore {
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        // Each run starts as a genuinely new anonymous person. The simulator
        // keeps a session across launches while `supabase db reset` takes
        // `auth.users` with it, so without this the second run authenticates as
        // someone the database has never heard of and every write fails a
        // foreign key — a test reporting last run's leftovers, not this one.
        try? await client.auth.signOut(scope: .local)
        return SupabaseTaperPlanStore(
            client: client,
            session: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client)),
            timeZone: zone
        )
    }

    /// 23:30 in Los Angeles, which is already tomorrow in UTC.
    ///
    /// Built in the pinned zone rather than the runner's, so the two days
    /// disagree on every machine this runs on.
    private var whenTheDaysDisagree: Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 9
        components.hour = 23
        components.minute = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: components)!
    }

    @Test("a dated plan round-trips to the table it was written for",
          .enabled(if: LocalBackend.isAvailable))
    func aDatedPlanRoundTrips() async throws {
        let capDay = whenTheDaysDisagree
        let quitDay = capDay.addingTimeInterval(56 * 86_400)
        let draft = TaperPlanDraft(
            startingCapMg: 18,
            currentCapMg: 18,
            capEffectiveFrom: capDay,
            quitDate: quitDay,
            firstUseMinutes: 20,
            sickInBed: true
        )

        let stored = try await store().save(draft)

        #expect(stored.startingCapMg == 18)
        #expect(stored.currentCapMg == 18)
        // The assertion that catches a timestamp sent to a date column: the day
        // that comes back is the day that went in, read the user's way.
        #expect(stored.capEffectiveFrom == "2025-10-09", "stored UTC day instead of the chosen one")
        #expect(stored.quitDate == "2025-12-04", "stored UTC day instead of the chosen one")
    }

    @Test("running onboarding twice moves the plan rather than failing",
          .enabled(if: LocalBackend.isAvailable))
    func asecondRunUpserts() async throws {
        // One row per person is a unique index, and nothing yet records that
        // onboarding was completed — so a second run is the ordinary case, not
        // an error. An insert would fail it with a constraint violation the
        // user cannot read.
        let day = Date(timeIntervalSince1970: 1_760_000_000)
        let store = await store()

        let first = try await store.save(
            TaperPlanDraft(startingCapMg: 18, currentCapMg: 18, capEffectiveFrom: day,
                           quitDate: nil, firstUseMinutes: 20, sickInBed: true)
        )
        let second = try await store.save(
            TaperPlanDraft(startingCapMg: 24, currentCapMg: 24, capEffectiveFrom: day,
                           quitDate: nil, firstUseMinutes: 3, sickInBed: false)
        )

        #expect(first.id == second.id, "a second run created a second plan")
        #expect(second.startingCapMg == 24)
    }
}
