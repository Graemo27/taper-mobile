import Foundation
import Testing
@testable import Taper

/// A store that records what it was asked to remove, and can refuse or stall.
private final class FakeRemover: PadKeyWriting, @unchecked Sendable {
    private(set) var reordered: [[Int]] = []

    func reorder(_ ids: [Int]) async throws -> [StoredPadKey] {
        lock.withLock { reordered.append(ids) }
        if fails { throw URLError(.notConnectedToInternet) }
        return []
    }

    private let lock = NSLock()
    private var state = State()

    private struct State {
        var removed: [Int] = []
        var fails = false
        var holds = false
    }

    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    /// Keeps a delete suspended, so the pad can be asked what it looks like
    /// while one is in flight.
    var holds: Bool {
        get { lock.withLock { state.holds } }
        set { lock.withLock { state.holds = newValue } }
    }
    var removed: [Int] { lock.withLock { state.removed } }

    func seed(_ keys: [PadKey]) async throws -> [StoredPadKey] { [] }

    func add(_ key: PadKey, ndc: String?) async throws -> StoredPadKey {
        Issue.record("editing added a key, which it has no path to do")
        return StoredPadKey(id: 0, form: key.form, label: key.label,
                            mg: key.mg, position: key.position, ndc: ndc)
    }

    func remove(_ id: Int) async throws {
        let shouldFail = lock.withLock {
            state.removed.append(id)
            return state.fails
        }
        while holds { await Task.yield() }
        if shouldFail { throw PadKeyWriteFailure.keyWasNotRemoved }
    }
}

/// Where a task reports back to the test, so the test can wait for a decision
/// rather than for a duration.
@MainActor
private final class Outcome {
    var decided = false
    var value: Int?
}

/// Waits with a deadline, so a condition that never comes reports rather than
/// hangs.
@MainActor
private func waitUntil(_ what: String, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(3)
    while !condition(), Date() < deadline { await Task.yield() }
    #expect(condition(), "\(what) never happened")
}

/// Covers editing the pad: what the mode allows, and what a failed removal
/// leaves behind.
@MainActor
struct PadEditRecordTests {
    @Test("removing a key reports it so the pad can drop it")
    func theCallerIsToldWhichKeyWent() async {
        // Returned rather than re-read, the same bargain adding makes: a read
        // issued now can be coalesced behind one already running.
        let store = FakeRemover()
        let edit = PadEditRecord(store: store)

        #expect(await edit.remove(7) == 7)
        #expect(store.removed == [7])
    }

    @Test("a removal that fails says so on the key it was for")
    func theMessageSitsWhereItHappened() async {
        // A pad is a grid of keys. A failure with no key attached would leave
        // somebody guessing which of six taps did not take.
        let store = FakeRemover()
        store.fails = true
        let edit = PadEditRecord(store: store)

        #expect(await edit.remove(7) == nil, "a failed removal reported a key")
        #expect(edit.failure == PadEditRecord.Failure(
            keyID: 7, message: "Couldn't remove that key. Try again."
        ))
    }

    @Test("retrying a key clears the message it is retrying")
    func aStaleFailureDoesNotOutliveTheRetry() async {
        // Left up, the old message reads as the retry having failed before it
        // finished.
        let store = FakeRemover()
        store.fails = true
        let edit = PadEditRecord(store: store)
        _ = await edit.remove(7)
        #expect(edit.failure != nil)

        store.fails = false
        #expect(await edit.remove(7) == 7)
        #expect(edit.failure == nil, "the message survived a removal that worked")
    }

    @Test("a key already going is not removed twice")
    func oneTapPerKey() async {
        // The badge is dimmed and disabled while a delete is in flight, but the
        // record refuses it too — a disabled control is a claim about the view,
        // not about the write.
        let store = FakeRemover()
        store.holds = true
        let edit = PadEditRecord(store: store)

        let first = Task { await edit.remove(7) }
        await waitUntil("the first delete") { store.removed == [7] }

        #expect(edit.isRemoving(7))

        // The second tap has to be *decided* before the first is released, or
        // this races: the first would clear `removing` and the second would
        // then be accepted for a reason the test is not about.
        //
        // Waited for by outcome rather than by awaiting it, because awaiting
        // hangs instead of failing when the guard is missing — the second call
        // reaches the held write and sits there. So the wait ends on either
        // answer: refused (the task finished without touching the store) or
        // accepted (the store saw a second attempt).
        let outcome = Outcome()
        let second = Task { @MainActor in
            outcome.value = await edit.remove(7)
            outcome.decided = true
        }
        await waitUntil("the second tap to be decided") {
            outcome.decided || store.removed.count == 2
        }

        #expect(outcome.decided, "the second tap reached the store instead of being refused")
        #expect(outcome.value == nil, "a second tap was accepted")

        store.holds = false
        _ = await first.value
        _ = await second.value
        #expect(store.removed == [7], "the key was removed twice")
    }

    @Test("two different keys can go at once")
    func neitherTapWaitsForTheOther() async {
        // Both taps are legitimate, and making the second wait would look like
        // it had not registered.
        let store = FakeRemover()
        store.holds = true
        let edit = PadEditRecord(store: store)

        let first = Task { await edit.remove(7) }
        let second = Task { await edit.remove(8) }
        await waitUntil("both deletes") { store.removed.sorted() == [7, 8] }

        store.holds = false
        _ = await first.value
        _ = await second.value
        #expect(edit.removing.isEmpty, "a key was left marked as going")
    }

    @Test("Done waits for whatever is still going")
    func themodeDoesNotCloseOverAWriteInFlight() async {
        // Closing would put the pad back with a key on it that is about to
        // vanish, which reads as the tap having done nothing.
        let store = FakeRemover()
        store.holds = true
        let edit = PadEditRecord(store: store)
        edit.startEditing()

        let going = Task { await edit.remove(7) }
        await waitUntil("the delete") { store.removed == [7] }

        #expect(edit.canFinish == false)
        edit.finishEditing()
        #expect(edit.isEditing, "Done closed over a delete in flight")

        store.holds = false
        _ = await going.value
        #expect(edit.canFinish)
        edit.finishEditing()
        #expect(edit.isEditing == false)
    }

    @Test("a build with no backend says so rather than failing quietly")
    func nothingToRemoveFrom() async {
        let edit = PadEditRecord(store: nil)

        #expect(await edit.remove(7) == nil)
        #expect(edit.failure == PadEditRecord.Failure(
            keyID: 7, message: PadEditRecord.noBackend
        ))
    }

    @Test("an arrangement that lands says nothing")
    func aSavedOrderIsNotAnEvent() async {
        // The pad already moved when this is called, so success has nothing
        // left to report: the thing somebody wanted to see happened before
        // the request went out.
        let store = FakeRemover()
        let record = PadEditRecord(store: store)

        #expect(await record.reorder([3, 1, 2]))
        #expect(store.reordered == [[3, 1, 2]], "the arrangement was not sent whole")
        #expect(record.failure == nil)
    }

    @Test("an arrangement that fails says the pad went back")
    func theUndoIsPartOfTheMessage() async {
        // Because it did go back — the caller reverts on false. Saying only
        // "couldn't save" would leave somebody believing an arrangement they
        // can no longer see is on its way.
        let store = FakeRemover()
        store.fails = true
        let record = PadEditRecord(store: store)

        #expect(await record.reorder([3, 1, 2]) == false)
        #expect(record.failure?.message == PadEditRecord.orderNotSaved)
        #expect(record.isReordering == false, "the pad was left unable to drag again")
    }

    @Test("a build with no backend cannot save an order either")
    func nothingToArrangeInto() async {
        let record = PadEditRecord(store: nil)

        #expect(await record.reorder([1]) == false)
        // Its own sentence: `noBackend` says nothing can be *removed*, which
        // is a true statement about a different button.
        #expect(record.failure?.message == PadEditRecord.noBackendForOrder)
        #expect(record.failure?.message.contains("rearranged") == true)
    }
}
