import Foundation
import Testing
@testable import Taper

/// A pad reader that returns what the test wants, or refuses.
private final class FakeReader: PadKeyReading, @unchecked Sendable {
    var keys: [StoredPadKey] = []
    var fails = false
    /// Holds a read open, so a second can be attempted while the first is in
    /// flight.
    var hangs = false

    private let lock = NSLock()
    private var _reads = 0
    var reads: Int { lock.withLock { _reads } }

    func currentKeys() async throws -> [StoredPadKey] {
        lock.withLock { _reads += 1 }
        if hangs { try await Task.sleep(for: .seconds(30)) }
        if fails { throw URLError(.notConnectedToInternet) }
        return keys
    }
}

private func key(
    _ id: Int,
    _ form: PadForm,
    label: String = "Key",
    position: Int = 0
) -> StoredPadKey {
    StoredPadKey(id: id, form: form, label: label, mg: 4, position: position, ndc: nil)
}

/// Covers grouping the pad the way the board draws it.
struct PadTests {
    @Test("treatment is drawn before what you are quitting")
    func theHelpfulLedgerComesFirst() {
        // The board puts what helps above what hurts. The read returns the
        // ledgers alphabetically — source before treatment — so trusting the
        // query's order would draw the screen upside down.
        let pad = Pad(keys: [key(1, .pouch), key(2, .patch)])

        #expect(pad.treatment.map(\.id) == [2])
        #expect(pad.sources.map(\.id) == [1])
    }

    @Test("keys within a ledger follow their position, not the order they arrived")
    func positionDecidesTheOrder() {
        let pad = Pad(keys: [
            key(1, .lozenge, position: 2),
            key(2, .patch, position: 0),
            key(3, .gum, position: 1),
        ])

        #expect(pad.treatment.map(\.id) == [2, 3, 1])
    }

    @Test("two keys sharing a position do not swap between reads")
    func tiesBreakOnIdSoThePadHoldsStill() {
        // `position` has no unique index — a duplicate is meant to be untidy
        // rather than broken — so without a tiebreak two keys are free to
        // change places every time the pad is read. A pad that reshuffles is
        // one nobody builds muscle memory on.
        let arrived = [key(9, .patch, position: 0), key(4, .lozenge, position: 0)]

        #expect(Pad(keys: arrived).treatment.map(\.id) == [4, 9])
        #expect(Pad(keys: arrived.reversed()).treatment.map(\.id) == [4, 9])
    }

    @Test("a pad with nothing on it is still a pad")
    func emptyIsAValueNotAFailure() {
        #expect(Pad().isEmpty)
        #expect(!Pad(keys: [key(1, .pouch)]).isEmpty)
    }
}

/// Covers what the app knows about the pad, and how it says it.
@MainActor
struct PadRecordTests {
    @Test("a pad on file is grouped and ready")
    func aPadIsLoaded() async {
        let reader = FakeReader()
        reader.keys = [key(1, .pouch, label: "Pouches"), key(2, .patch, label: "Patch")]
        let record = PadRecord(store: reader)

        await record.load()

        guard case let .ready(pad) = record.status else {
            Issue.record("a pad on file was not reported as ready")
            return
        }
        #expect(pad.treatment.map(\.label) == ["Patch"])
        #expect(pad.sources.map(\.label) == ["Pouches"])
    }

    @Test("an empty pad is ready and empty, not a failure")
    func nothingOnThePadIsNotAnError() async {
        // What everyone who has not finished onboarding has. Reported as a
        // failure it would send somebody to a retry button that can never
        // succeed.
        let record = PadRecord(store: FakeReader())

        await record.load()

        #expect(record.status == .ready(Pad()))
    }

    @Test("a read that fails is not read as an empty pad")
    func aFailedReadIsNotAnAbsence() async {
        // The distinction that matters once the pad can be edited: drawing
        // "no keys yet" over a failed read invites somebody to rebuild a pad
        // that is already on the server.
        let reader = FakeReader()
        reader.keys = [key(1, .pouch)]
        reader.fails = true
        let record = PadRecord(store: reader)

        await record.load()

        guard case let .unavailable(message) = record.status else {
            Issue.record("a failed read did not reach the unavailable state")
            return
        }
        #expect(record.status != .ready(Pad()))
        #expect(message.contains("try again"))
        #expect(!message.contains("URLError"))
    }

    @Test("a build with no backend says so, rather than blaming the connection")
    func aMissingBackendIsItsOwnSentence() async {
        let record = PadRecord(store: nil)

        await record.load()

        guard case let .unavailable(message) = record.status else {
            Issue.record("a build with no backend did not report the pad unavailable")
            return
        }
        #expect(message.contains("no backend"))
        #expect(!message.contains("connection"))
    }

    @Test("a failed read can be retried without restarting the app")
    func aFailureIsRecoverable() async {
        let reader = FakeReader()
        reader.keys = [key(1, .pouch)]
        reader.fails = true
        let record = PadRecord(store: reader)
        await record.load()

        reader.fails = false
        await record.load()

        #expect(record.status != .unavailable(""))
        #expect(reader.reads == 2)
    }

    @Test("a second read does not start while the first is in flight")
    func concurrentLoadsAreSerialised() async {
        // One tap on a retry issues two reads: the retry sets `loading`, which
        // renders, whose task starts another. Whichever lands last wins, so a
        // stale failure can put the error back in front of somebody whose pad
        // had just arrived.
        let reader = FakeReader()
        reader.hangs = true
        let record = PadRecord(store: reader)

        let first = Task { await record.load() }

        // Bounded, because an unbounded wait turns a regression here into a
        // suite that hangs rather than one that fails.
        let deadline = Date().addingTimeInterval(2)
        while reader.reads == 0, Date() < deadline {
            await Task.yield()
        }
        #expect(reader.reads == 1, "the first read never started")

        await record.load()

        #expect(reader.reads == 1, "a second read started while the first was in flight")
        first.cancel()
    }
}
