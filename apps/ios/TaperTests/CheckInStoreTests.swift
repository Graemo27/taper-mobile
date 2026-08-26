import Foundation
import Supabase
import Testing
@testable import Taper

/// Drives the check-in store against a real Postgres with the real migrations
/// applied.
///
/// An extension of `LiveBackendTests`, because these tests share the one
/// persisted session the other live suites use. What only a database can show
/// here is the snapshot: `check_ins` copies four fields off a key at the moment
/// of the tap, and a store that quietly wrote a reference instead would pass
/// every test that does not read the row back.
extension LiveBackendTests {
    /// Fixed, and deliberately not the runner's — on a UTC runner no local time
    /// disagrees with UTC, so a day that serialized wrongly still round-trips.
    private var loggingZone: TimeZone { TimeZone(identifier: "America/Los_Angeles")! }

    private func checkInBackend() async -> (SupabaseCheckInStore, SupabasePadKeyStore) {
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        try? await client.auth.signOut(scope: .local)
        let session = SessionCoordinator(auth: SupabaseAnonymousAuth(client: client))
        return (
            SupabaseCheckInStore(client: client, session: session, timeZone: loggingZone),
            SupabasePadKeyStore(client: client, session: session)
        )
    }

    /// 23:30 in Los Angeles, which is already tomorrow in UTC.
    private var whenTheDaysDisagreeForLogging: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = loggingZone
        return calendar.date(from: DateComponents(
            year: 2025, month: 10, day: 9, hour: 23, minute: 30
        ))!
    }

    private func seededKey(_ pad: SupabasePadKeyStore) async throws -> StoredPadKey {
        let keys = try await pad.seed([PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0)])
        return try #require(keys.first)
    }

    @Test("a tap is written as a snapshot, not as a reference",
          .enabled(if: LocalBackend.isAvailable))
    func anEntryCarriesItsOwnCopyOfTheKey() async throws {
        // The whole reason `check_ins` repeats four columns the pad already
        // has. Correcting a key's strength must not rewrite last Tuesday, and
        // the day's list has to render without a join.
        let (checkIns, pad) = await checkInBackend()
        let key = try await seededKey(pad)

        let logged = try await checkIns.log(
            CheckInDraft(pending: PendingEntry(key: key, quantity: 2), day: Date())
        )

        #expect(logged.label == "Pouches")
        // `created_at` is a `timestamptz`, which is a type boundary no fake
        // crosses. If the decoder cannot read what Postgres writes, this is
        // where it fails rather than on a screen.
        #expect(
            abs(logged.createdAt.timeIntervalSinceNow) < 300,
            "created_at came back as \(logged.createdAt), which is not about now"
        )
        #expect(logged.form == .pouch)
        #expect(logged.mg == 6)
        #expect(logged.quantity == 2)
        #expect(logged.ledger == .source, "the ledger was not written as the key's")

        // Read back rather than trusting what the write returned. The two are
        // different paths — one is the row PostgREST echoed, the other is the
        // decode the day's screen actually uses — and a snapshot that only
        // survives the first is not a snapshot.
        let stored = try #require(try await checkIns.entries(on: Date()).first)
        #expect(stored == logged, "the entry read back was not the entry written")
    }

    @Test("a craving that passed is written with no key and no dose",
          .enabled(if: LocalBackend.isAvailable))
    func anUrgeReachesPostgres() async throws {
        // Two things no row in this table has ever had: a null `pad_key_id` and
        // a zero `mg`. The column accepted neither until this week, and the
        // encoder sent neither — `CheckInRow.padKeyID` was a plain `Int`, so
        // the shape the migration allows was still unreachable from the app.
        let (checkIns, _) = await checkInBackend()

        // One instant for the write and the read. Two `Date()` calls straddle
        // midnight roughly once in a hundred thousand runs, and when they do
        // the read asks a different day than the write answered — the same
        // boundary `logged_on` exists to pin down, arriving in the test rather
        // than in the column.
        let moment = Date()

        let logged = try await checkIns.log(.urgePassed(on: moment))

        #expect(logged.mg == 0, "an urge was written as a dose")
        #expect(logged.label == CheckInDraft.urgeLabel)
        #expect(logged.ledger == .treatment)
        // Read back rather than trusted from the insert's own echo: a null
        // foreign key is exactly the sort of thing a round trip settles.
        let day = try await checkIns.entries(from: moment, to: moment)
        #expect(day.contains { $0.label == CheckInDraft.urgeLabel },
                "the urge did not come back with the day")
    }

    @Test("the day an entry lands on is the user's day, not UTC's",
          .enabled(if: LocalBackend.isAvailable))
    func aLateEveningEntryStaysOnItsOwnDay() async throws {
        // A check-in at 9pm in California landing on tomorrow makes two days'
        // totals wrong at once — and the cap is read against exactly that
        // total. The plan store already learned this; the same function is
        // used here so there is one answer rather than two.
        let (checkIns, pad) = await checkInBackend()
        let key = try await seededKey(pad)
        let lateEvening = whenTheDaysDisagreeForLogging

        _ = try await checkIns.log(
            CheckInDraft(pending: PendingEntry(key: key), day: lateEvening)
        )

        #expect(try await checkIns.entries(on: lateEvening).count == 1)
        // The same instant read in UTC genuinely is the next day, so the
        // assertion above discriminates rather than passing incidentally.
        #expect(
            PlanDay.wireFormat(lateEvening, timeZone: TimeZone(identifier: "UTC")!) == "2025-10-10",
            "the fixture no longer straddles midnight"
        )
        let nextDay = lateEvening.addingTimeInterval(86_400)
        #expect(try await checkIns.entries(on: nextDay).isEmpty, "the entry landed on the wrong day")
    }

    @Test("a day with nothing on it reads as empty, rather than failing",
          .enabled(if: LocalBackend.isAvailable))
    func anUntouchedDayIsNotAnError() async throws {
        // Every day starts this way, and the tally asks before anything is on
        // screen. An error here would be indistinguishable from a read that
        // genuinely failed.
        let (checkIns, _) = await checkInBackend()

        #expect(try await checkIns.entries(on: Date()).isEmpty)
    }

    @Test("a span reads back every day in it and nothing either side",
          .enabled(if: LocalBackend.isAvailable))
    func aRangeIsInclusiveOfBothEnds() async throws {
        // `gte`/`lte` on a date column against strings the client formats: a
        // boundary that is exclusive at one end, or a comparison Postgres does
        // as text rather than as a date, both read as a week that is quietly
        // missing a day. No fake can tell me which.
        let (checkIns, pad) = await checkInBackend()
        let key = try await seededKey(pad)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)!
        }

        // One on each end of the span, and one the day before it — each with a
        // different quantity, because `StoredCheckIn` carries no `logged_on`
        // and a count alone cannot tell a correct window from one shifted a day
        // off. Rows come back in id order, which is insertion order.
        for (offset, quantity) in [(-3, 3), (-2, 2), (-1, 1)] {
            _ = try await checkIns.log(
                CheckInDraft(pending: PendingEntry(key: key, quantity: quantity), day: day(offset))
            )
        }

        let span = try await checkIns.entries(from: day(-2), to: day(-1))
        #expect(span.map(\.quantity) == [2, 1], "the span took the wrong two days")

        let outside = try await checkIns.entries(from: day(-3), to: day(-3))
        #expect(outside.map(\.quantity) == [3], "a single day read as a span lost or borrowed a row")

        // Handed over backwards, which a caller doing date arithmetic will do
        // eventually. It has to mean the same span rather than an empty one.
        let reversed = try await checkIns.entries(from: day(-1), to: day(-2))
        #expect(reversed.map(\.quantity) == span.map(\.quantity), "a backwards span read differently")
    }

    @Test("a day reads back in the order it was logged",
          .enabled(if: LocalBackend.isAvailable))
    func theDayIsInTapOrder() async throws {
        let (checkIns, pad) = await checkInBackend()
        let key = try await seededKey(pad)
        let day = whenTheDaysDisagreeForLogging

        for quantity in [1, 2, 3] {
            _ = try await checkIns.log(
                CheckInDraft(pending: PendingEntry(key: key, quantity: quantity), day: day)
            )
        }

        #expect(try await checkIns.entries(on: day).map(\.quantity) == [1, 2, 3])
    }

    @Test("an entry can be taken back off the day",
          .enabled(if: LocalBackend.isAvailable))
    func removingAnEntryLeavesTheDay() async throws {
        // `check_ins` grants delete to its owner, unlike `taper_plans` which
        // grants none — the difference is deliberate and this is the half that
        // uses it. A log nobody can correct is one people stop trusting.
        let (checkIns, pad) = await checkInBackend()
        let key = try await seededKey(pad)
        let day = whenTheDaysDisagreeForLogging
        let first = try await checkIns.log(CheckInDraft(pending: PendingEntry(key: key), day: day))
        _ = try await checkIns.log(
            CheckInDraft(pending: PendingEntry(key: key, quantity: 2), day: day)
        )
        #expect(try await checkIns.entries(on: day).count == 2)

        try await checkIns.remove(first.id)

        let left = try await checkIns.entries(on: day)
        #expect(left.count == 1)
        #expect(left.first?.quantity == 2, "the wrong entry was removed")
    }

    @Test("removing an entry that is already gone is not an error",
          .enabled(if: LocalBackend.isAvailable))
    func aSecondRemovalIsQuiet() async throws {
        // Two screens can be open on the same day, and a delete matching no
        // rows is how Postgres reports "already gone". Raising on it would
        // send somebody a failure about a correction that had happened.
        let (checkIns, pad) = await checkInBackend()
        let key = try await seededKey(pad)
        let day = whenTheDaysDisagreeForLogging
        let entry = try await checkIns.log(CheckInDraft(pending: PendingEntry(key: key), day: day))

        try await checkIns.remove(entry.id)
        try await checkIns.remove(entry.id)

        #expect(try await checkIns.entries(on: day).isEmpty)
    }

    @Test("the check-in suite leaves no session behind",
          .enabled(if: LocalBackend.isAvailable))
    func checkInTestsSignOutWhenDone() async throws {
        // Teardown as a test, because `.serialized` runs in source order and
        // `deinit` cannot await.
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        try await client.auth.signOut(scope: .local)

        await #expect(throws: (any Error).self) {
            try await client.auth.session
        }
    }
}
