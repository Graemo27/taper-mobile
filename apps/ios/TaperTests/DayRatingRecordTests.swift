import Foundation
import Testing
@testable import Taper

/// A rating store that remembers, and can refuse.
private final class FakeRatings: DayRatingStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()

    private struct State {
        var stored: DayRating?
        var fails = false
        var holds = false
        var reads = 0
    }

    var stored: DayRating? {
        get { lock.withLock { state.stored } }
        set { lock.withLock { state.stored = newValue } }
    }
    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    var reads: Int { lock.withLock { state.reads } }
    var holds: Bool {
        get { lock.withLock { state.holds } }
        set { lock.withLock { state.holds = newValue } }
    }

    func rating(on day: Date) async throws -> DayRating? {
        // Snapshotted at call time and returned after the hold, because that
        // is what a real response is: the database as the query saw it, not
        // as it stands when the bytes finally arrive.
        let (snapshot, fails) = lock.withLock { state.reads += 1
            return (state.stored, state.fails) }
        while holds { await Task.yield() }
        if fails { throw URLError(.notConnectedToInternet) }
        return snapshot
    }
    func rate(_ rating: DayRating, on day: Date) async throws {
        try lock.withLock {
            if state.fails { throw URLError(.notConnectedToInternet) }
            state.stored = rating
        }
    }
    func clearRating(on day: Date) async throws {
        try lock.withLock {
            if state.fails { throw URLError(.notConnectedToInternet) }
            state.stored = nil
        }
    }
}

/// Covers the daily check-in's state: answering, changing, un-answering, and
/// what a failure puts back.
@MainActor
struct DayRatingRecordTests {
    @Test("today's answer is read back onto the card")
    func theCardRemembersAcrossLaunches() async {
        let store = FakeRatings()
        store.stored = .soSo
        let record = DayRatingRecord(store: store)

        await record.load()

        #expect(record.rating == .soSo)
    }

    @Test("an answer is shown the moment it is tapped, and saved")
    func answeringIsInstant() async {
        let store = FakeRatings()
        let record = DayRatingRecord(store: store)

        await record.tapped(.rough)

        #expect(record.rating == .rough)
        #expect(store.stored == .rough)
    }

    @Test("tapping the answer again takes it back")
    func skipFreelyIncludesUnAnswering() async {
        let store = FakeRatings()
        store.stored = .easy
        let record = DayRatingRecord(store: store)
        await record.load()

        await record.tapped(.easy)

        #expect(record.rating == nil, "the answer stayed selected")
        #expect(store.stored == nil, "the row survived un-answering")
    }

    @Test("a failed save puts the old answer back and says so")
    func theOptimismIsHonest() async {
        // The chip fills on the tap — a claim about the server. When the
        // server says no, the claim has to be withdrawn where it was made.
        let store = FakeRatings()
        store.stored = .easy
        let record = DayRatingRecord(store: store)
        await record.load()

        store.fails = true
        await record.tapped(.rough)

        #expect(record.rating == .easy, "a failed answer stayed on the card")
        #expect(record.failureText == "Couldn't save that. Try again.")

        store.fails = false
        await record.tapped(.rough)
        #expect(record.rating == .rough)
        #expect(record.failureText == nil, "the note outlived the retry that worked")
    }

    @Test("a failed read leaves the card unanswered, not nagging")
    func anOptionalCardDoesNotDemandItsAnswer() async {
        // The one optional surface on home. A card that posts an error about
        // not knowing the answer to an optional question has made it
        // mandatory — and the write is an upsert, so a stale blank is safe to
        // act on.
        let store = FakeRatings()
        store.stored = .easy
        store.fails = true
        let record = DayRatingRecord(store: store)

        await record.load()

        #expect(record.rating == nil)
        #expect(record.failureText == nil, "an optional card nagged about a failed read")
    }

    @Test("a build with no backend says so on the first tap")
    func nothingToSaveInto() async {
        let record = DayRatingRecord(store: nil)

        await record.tapped(.easy)

        #expect(record.rating == nil)
        #expect(record.failureText == DayRatingRecord.noBackend)
    }

    @Test("a new day's blank is an answer, not a gap to keep yesterday in")
    func yesterdaysWordDoesNotSurviveMidnight() async {
        // The app stays open across midnight, the new day has no rating, and
        // a read that treats nil as "keep what I had" shows yesterday's chip
        // selected on a day nobody rated.
        let store = FakeRatings()
        store.stored = .rough
        let record = DayRatingRecord(store: store)
        await record.load()
        #expect(record.rating == .rough)

        store.stored = nil
        await record.load()
        #expect(record.rating == nil, "yesterday's answer survived into an unanswered day")
    }

    @Test("a read a tap overtook is dropped, not published")
    func theTapIsNewer() async {
        // load() starts, a chip is tapped while it is open, and the old
        // response lands after the optimistic save — publishing it would put
        // the stale value over the user's newest intent.
        let store = FakeRatings()
        store.stored = .easy
        let record = DayRatingRecord(store: store)

        store.holds = true
        let reading = Task { await record.load() }
        let deadline = Date().addingTimeInterval(2)
        while store.reads == 0, Date() < deadline { await Task.yield() }

        store.holds = false
        await record.tapped(.rough)
        _ = await reading.value

        #expect(record.rating == .rough, "a stale read overwrote a newer tap")
        #expect(store.stored == .rough)
    }

    @Test("the words are the board's, hyphen included")
    func theWireTokenIsNotTheCopy() {
        #expect(DayRating.easy.word == "Easy")
        #expect(DayRating.soSo.word == "So-so")
        #expect(DayRating.rough.word == "Rough")
    }
}
