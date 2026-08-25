import Foundation
import Testing
@testable import Taper

/// A pad reader that returns what the test wants, or refuses.
///
/// Every field is behind the lock. `currentKeys` is nonisolated and runs on
/// whatever thread the task lands on, while the test setting up the next answer
/// is on the main actor — the same race Thread Sanitizer caught in
/// `TreatmentSearchTests`' catalogue, which was also a plain `var` on an
/// `@unchecked Sendable` fake.
private final class FakeReader: PadKeyReading, @unchecked Sendable {
    /// Everything a read consults, as one value.
    private struct Answers {
        var keys: [StoredPadKey] = []
        var fails = false
        var hangs = false
        var holds = false
        var throwsCancelledRequest = false
        var reads = 0
    }

    private let lock = NSLock()
    private var state = Answers()

    var keys: [StoredPadKey] {
        get { lock.withLock { state.keys } }
        set { lock.withLock { state.keys = newValue } }
    }
    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    /// Holds a read open, so a second can be attempted while the first is in
    /// flight.
    var hangs: Bool {
        get { lock.withLock { state.hangs } }
        set { lock.withLock { state.hangs = newValue } }
    }
    /// Holds a read open until it is let go, unlike `hangs` — a sleep cannot be
    /// shortened, and a test that needs the first read to *finish* after a
    /// second was queued has to be able to release it.
    var holds: Bool {
        get { lock.withLock { state.holds } }
        set { lock.withLock { state.holds = newValue } }
    }
    /// Waits for cancellation and then throws the way a cancelled URL request
    /// does — `URLError.cancelled`, not `CancellationError`. The two arrive by
    /// different routes and only one of them is a `catch` pattern.
    var throwsCancelledRequest: Bool {
        get { lock.withLock { state.throwsCancelledRequest } }
        set { lock.withLock { state.throwsCancelledRequest = newValue } }
    }
    var reads: Int { lock.withLock { state.reads } }

    func currentKeys() async throws -> [StoredPadKey] {
        // Snapshotted on entry, before any waiting. A read answers with what
        // the pad held when it was *issued* — which is the whole point of the
        // coalescing test, where a write lands while a read is in flight.
        // Returning `keys` after the hold released meant the first read could
        // see the new key, and the assertion that the queued read fetched it
        // passed without the queued read mattering.
        let answers = lock.withLock {
            state.reads += 1
            return state
        }
        if answers.throwsCancelledRequest {
            while !Task.isCancelled { await Task.yield() }
            throw URLError(.cancelled)
        }
        while holds { await Task.yield() }
        if answers.hangs { try await Task.sleep(for: .seconds(30)) }
        if answers.fails { throw URLError(.notConnectedToInternet) }
        return answers.keys
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

/// Covers a key arriving from a save rather than from a read.
@MainActor
struct PadInsertTests {
    private func key(_ id: Int, _ form: PadForm, _ label: String, position: Int) -> StoredPadKey {
        StoredPadKey(id: id, form: form, label: label, mg: 2, position: position, ndc: nil)
    }

    private func loaded(_ keys: [StoredPadKey]) async -> PadRecord {
        let reader = FakeReader()
        reader.keys = keys
        let record = PadRecord(store: reader)
        await record.load()
        return record
    }

    @Test("two saves close together both reach the pad")
    func neitherKeyIsDropped() async {
        // `load()` drops a read that arrives while one is running, on purpose.
        // So two saves close enough together shared one read, and if it went
        // out before the second write, that key was missing until something
        // else reloaded — indistinguishable from a save that did not work.
        let record = await loaded([key(1, .pouch, "Pouches", position: 0)])

        #expect(record.insert(key(2, .vape, "Vape", position: 1)))
        #expect(record.insert(key(3, .gum, "Gum", position: 0)))

        guard case let .ready(pad) = record.status else {
            Issue.record("the pad stopped being ready")
            return
        }
        #expect(pad.sources.map(\.id) == [1, 2], "a source key was dropped")
        #expect(pad.treatment.map(\.id) == [3], "the treatment key was dropped")
    }

    @Test("an inserted key lands where the next read would have put it")
    func itDoesNotJustGoOnTheEnd() async {
        // The row carries the position Postgres assigned, and `Pad` sorts by
        // `(position, id)` — so a key that belongs in the middle goes there
        // rather than wherever it happened to arrive.
        let record = await loaded([
            key(1, .pouch, "First", position: 0),
            key(3, .pouch, "Third", position: 2),
        ])

        record.insert(key(2, .pouch, "Second", position: 1))

        guard case let .ready(pad) = record.status else {
            Issue.record("the pad stopped being ready")
            return
        }
        #expect(pad.sources.map(\.label) == ["First", "Second", "Third"])
    }

    @Test("a pad that is not ready refuses the key rather than inventing one")
    func thereIsNothingToAddTo() async {
        // Appending to a state that is not `ready` would draw a pad of one key
        // over a read that failed, or over one still running. The caller reads
        // instead, which is what the returned flag is for.
        let stillLoading = PadRecord(store: FakeReader())
        #expect(stillLoading.status == .loading, "the fixture did not start loading")
        #expect(stillLoading.insert(key(1, .pouch, "Pouches", position: 0)) == false,
                "a pad still loading accepted a key it had nowhere to put")
        #expect(stillLoading.status == .loading, "the status changed anyway")

        let failed = PadRecord(store: nil)
        await failed.load()
        guard case .unavailable = failed.status else {
            Issue.record("the fixture did not reach unavailable")
            return
        }
        #expect(failed.insert(key(1, .pouch, "Pouches", position: 0)) == false,
                "a failed read accepted a key")
        guard case .unavailable = failed.status else {
            Issue.record("a refused insert changed the status")
            return
        }
    }
}

/// Covers a read that was already running when a key was written.
@MainActor
struct PadReloadCoalescingTests {
    private func key(_ id: Int, position: Int) -> StoredPadKey {
        StoredPadKey(id: id, form: .pouch, label: "Key \(id)", mg: 2,
                     position: position, ndc: nil)
    }

    /// Waits with a deadline, and says so when it runs out.
    ///
    /// The same shape `TreatmentSearchTests` uses, for the reason this file
    /// learned the hard way: an unbounded `while !condition { await
    /// Task.yield() }` does not fail when the thing never happens, it hangs —
    /// and a suite that hangs reports a timeout somewhere else entirely rather
    /// than the assertion that would have named the fault.
    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { await Task.yield() }
        #expect(condition(), "\(what) never happened")
    }

    @Test("a key written during a read is not lost when the read predates it")
    func theQueuedReadStillHappens() async {
        // `insert` refuses a pad that is not `ready`, so a save landing
        // mid-load falls back to a read. That read used to be dropped by the
        // one already running — and the running one was issued *before* the
        // write, so its answer cannot contain the key. The pad then showed a
        // key as missing after a save that said it worked.
        let reader = FakeReader()
        reader.keys = [key(1, position: 0)]
        reader.holds = true
        let record = PadRecord(store: reader)

        let loading = Task { await record.load() }
        await waitUntil("the first read") { reader.reads == 1 }

        // The save lands. There is no pad to put it on yet, so the caller reads.
        #expect(record.insert(key(2, position: 1)) == false,
                "the fixture was not mid-load")

        // Awaited here rather than started in a `Task`, which would only *hope*
        // to enter while the first read was held. `load()` returns as soon as
        // it sees one running, so this is the interleaving the test is about
        // rather than a race it is trying to win.
        await record.load()

        // Visible to a read issued from now on. The one still running
        // snapshotted the pad before this line.
        reader.keys = [key(1, position: 0), key(2, position: 1)]
        reader.holds = false
        await loading.value

        guard case let .ready(pad) = record.status else {
            Issue.record("the pad never became ready")
            return
        }
        #expect(pad.sources.map(\.id) == [1, 2],
                "the key written during the read never arrived")
        #expect(reader.reads == 2, "the second read was dropped rather than queued")
    }
}

