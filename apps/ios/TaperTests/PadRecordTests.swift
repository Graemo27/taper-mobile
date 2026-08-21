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
    /// Waits for cancellation and then throws the way a cancelled URL request
    /// does — `URLError.cancelled`, not `CancellationError`. The two arrive by
    /// different routes and only one of them is a `catch` pattern.
    var throwsCancelledRequest = false

    private let lock = NSLock()
    private var _reads = 0
    var reads: Int { lock.withLock { _reads } }

    func currentKeys() async throws -> [StoredPadKey] {
        lock.withLock { _reads += 1 }
        if throwsCancelledRequest {
            while !Task.isCancelled { await Task.yield() }
            throw URLError(.cancelled)
        }
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

        // The pad it should now be showing, not merely "some state other than
        // one particular failure message" — which the previous assertion was,
        // and which a retry that failed differently would have satisfied.
        #expect(record.status == .ready(Pad(keys: reader.keys)))
        #expect(reader.reads == 2)
    }

    @Test("a read abandoned mid-flight is not reported as a connection failure")
    func cancellingAReadSaysNothing() async {
        // The read is driven by a view's `task`, so it is cancelled exactly
        // when somebody navigates away. `Task.sleep` throws `CancellationError`
        // from inside the store, and catching that as a failure would put
        // "check your connection" on screen for a connection that was fine.
        let reader = FakeReader()
        reader.hangs = true
        let record = PadRecord(store: reader)

        let task = Task { await record.load() }
        await waitForFirstRead(reader)
        task.cancel()
        await task.value

        #expect(record.status == .loading, "an abandoned read reported something")
    }

    @Test("a request cancelled in flight is not reported either")
    func aCancelledRequestSaysNothing() async {
        // The other half, and the reason a `catch is CancellationError` alone
        // is not enough: URLSession reports a cancelled request as
        // `URLError.cancelled`, which is an ordinary error until the task's
        // own cancellation flag is consulted.
        let reader = FakeReader()
        reader.throwsCancelledRequest = true
        let record = PadRecord(store: reader)

        let task = Task { await record.load() }
        await waitForFirstRead(reader)
        task.cancel()
        await task.value

        #expect(record.status == .loading, "a cancelled request was reported as a failure")
    }

    /// Waits for the read to actually start, with a bound — an unbounded wait
    /// turns a regression into a suite that hangs rather than one that fails.
    private func waitForFirstRead(_ reader: FakeReader) async {
        let deadline = Date().addingTimeInterval(2)
        while reader.reads == 0, Date() < deadline {
            await Task.yield()
        }
        #expect(reader.reads == 1, "the read never started")
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
        // `cancel()` only asks. Returning here would leave a 30-second sleep
        // running past the end of the test, inside a suite that runs its cases
        // concurrently.
        first.cancel()
        await first.value
    }
}

/// Covers which forms the app has a mark for.
@MainActor
struct PadKeyMarkTests {
    @Test("only the forms the board has drawn get a mark")
    func theUndrawnFormsAreKnownAndListed() {
        // A test rather than only a comment, because the gap is a design
        // decision waiting on someone: the board has drawn four marks, and the
        // other six would have to be invented. Pinning the split here means
        // adding a mark is a deliberate edit rather than something that drifts
        // in, and it keeps the list of what is missing somewhere it can be
        // read off rather than counted by eye.
        let drawn = PadForm.allCases.filter { PadKeyMark.isDrawn($0) }
        #expect(Set(drawn) == [.patch, .lozenge, .pouch, .vape])

        // Cigarettes are the most common thing anyone quits, so the most-used
        // key in the app is one of the ones with no mark.
        #expect(!PadKeyMark.isDrawn(.cigarette))
    }
}
