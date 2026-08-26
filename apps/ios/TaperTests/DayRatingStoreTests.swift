import Foundation
import Testing
@testable import Taper

/// Drives the rating store against a real Postgres with the real migrations
/// applied.
///
/// What only a database can show here is the upsert: `rate` twice on one day
/// must land on one row via the unique constraint, and a store that quietly
/// inserted twice would pass every test that does not read the count back.
extension LiveBackendTests {
    private var ratingZone: TimeZone { TimeZone(identifier: "America/Los_Angeles")! }

    private func ratingBackend() async -> SupabaseDayRatingStore {
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        try? await client.auth.signOut(scope: .local)
        let session = SessionCoordinator(auth: SupabaseAnonymousAuth(client: client))
        return SupabaseDayRatingStore(client: client, session: session, timeZone: ratingZone)
    }

    /// A date built from parts, in the rating zone.
    ///
    /// Component-built for every test day, after the first draft derived its
    /// days with `addingTimeInterval` and walked straight into the November
    /// DST fall-back: 21 days of seconds before Nov 12 23:30 is Oct 23 *00:30*,
    /// so "an hour later" was the same local day and the test refuted itself.
    private func laDate(month: Int, day: Int, hour: Int, minute: Int = 30) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ratingZone
        return calendar.date(from: DateComponents(
            year: 2025, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    @Test("a changed mind lands on the same row, and reads back changed",
          .enabled(if: LocalBackend.isAvailable))
    func oneJudgementPerDay() async throws {
        let store = await ratingBackend()
        let day = laDate(month: 11, day: 12, hour: 12)

        try await store.rate(.rough, on: day)
        try await store.rate(.easy, on: day)

        #expect(try await store.rating(on: day) == .easy)
        try await store.clearRating(on: day)
    }

    @Test("an unanswered day answers nil, not an error",
          .enabled(if: LocalBackend.isAvailable))
    func absenceIsTheDefault() async throws {
        let store = await ratingBackend()

        #expect(try await store.rating(on: laDate(month: 10, day: 29, hour: 12)) == nil)
    }

    @Test("a cleared answer is taken back, as skip freely requires",
          .enabled(if: LocalBackend.isAvailable))
    func unAnsweringIsPartOfOptional() async throws {
        let store = await ratingBackend()
        let day = laDate(month: 11, day: 5, hour: 12)

        try await store.rate(.soSo, on: day)
        try await store.clearRating(on: day)

        #expect(try await store.rating(on: day) == nil)
    }

    @Test("the rating lands on the reader's day, not the server's",
          .enabled(if: LocalBackend.isAvailable))
    func aLateNightAnswerStaysOnItsDay() async throws {
        // 23:30 in Los Angeles is already tomorrow in UTC. Written with the
        // reader's zone and read back with it: a store that derived the day
        // from the server's clock would file this on the wrong page.
        let store = await ratingBackend()
        let lateNight = laDate(month: 10, day: 22, hour: 23)
        let nextLocalDay = laDate(month: 10, day: 23, hour: 0)

        try await store.rate(.rough, on: lateNight)

        #expect(try await store.rating(on: lateNight) == .rough)
        #expect(try await store.rating(on: nextLocalDay) == nil,
                "the half hour before midnight leaked into the next day")
        try await store.clearRating(on: lateNight)
    }
}
