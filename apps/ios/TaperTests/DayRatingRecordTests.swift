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

    func rating(on day: Date) async throws -> DayRating? {
        try lock.withLock {
            state.reads += 1
            if state.fails { throw URLError(.notConnectedToInternet) }
            return state.stored
        }
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

    @Test("the words are the board's, hyphen included")
    func theWireTokenIsNotTheCopy() {
        #expect(DayRating.easy.word == "Easy")
        #expect(DayRating.soSo.word == "So-so")
        #expect(DayRating.rough.word == "Rough")
    }
}
