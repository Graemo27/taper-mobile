import Foundation
import Testing
@testable import Taper

/// A check-in store that does what the test needs and counts what it was asked.
private final class FakeCheckIns: CheckInStoring, @unchecked Sendable {
    var existing: [StoredCheckIn] = []
    var readFails = false
    /// Holds a read open, so a second can be attempted while the first is in
    /// flight.
    var readHangs = false

    private let lock = NSLock()
    private var _writes: [CheckInDraft] = []
    private var _reads = 0
    /// Every draft it was asked to log, in order. Drafts rather than a count,
    /// so a retry sending a different quantity is distinguishable from a repeat.
    var writes: [CheckInDraft] { lock.withLock { _writes } }
    var reads: Int { lock.withLock { _reads } }

    func entries(on day: Date) async throws -> [StoredCheckIn] {
        lock.withLock { _reads += 1 }
        if readHangs { try await Task.sleep(for: .seconds(30)) }
        if readFails { throw URLError(.notConnectedToInternet) }
        return existing
    }

    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn {
        lock.withLock { _writes.append(draft) }
        return StoredCheckIn(
            id: writes.count, ledger: draft.key.ledger, label: draft.key.label,
            form: draft.key.form, mg: draft.key.mg, quantity: draft.quantity
        )
    }
}

private func key(_ id: Int, mg: Double = 3, label: String = "Pouches") -> StoredPadKey {
    StoredPadKey(id: id, form: .pouch, label: label, mg: mg, position: 0, ndc: nil)
}

/// Covers reading today, and folding a pending tap into its tally.
@MainActor
struct TodayRecordTests {
    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func record(_ store: FakeCheckIns) -> TodayRecord {
        TodayRecord(store: store, day: { self.day })
    }

    @Test("today is read into the tally, and a pending tap is folded on top")
    func theTallyIsBuiltFromBoth() async {
        let store = FakeCheckIns()
        store.existing = [
            StoredCheckIn(id: 1, ledger: .source, label: "Pouches", form: .pouch, mg: 3, quantity: 2)
        ]
        let record = record(store)

        await record.load()
        record.selection.tap(key(9, mg: 1.5))

        let tally = record.tally(ceilingMg: 12)
        #expect(tally.loggedMg == 6, "what was already on the day did not reach the tally")
        #expect(tally.pendingMg == 1.5)
        #expect(tally.projectedMg == 7.5)
    }

    @Test("a day that cannot be read is not an empty day")
    func aFailedReadIsNotAnEmptyDay() async {
        // Showing "nothing logged yet" over a failed read invites somebody to
        // log a second time against a day the app could not see.
        let store = FakeCheckIns()
        store.readFails = true
        let record = record(store)

        await record.load()

        guard case let .unavailable(message) = record.status else {
            Issue.record("a failed read did not reach the unavailable state")
            return
        }
        #expect(message.contains("try again"))
        #expect(!message.contains("URLError"))
    }

    @Test("a build with no backend says so rather than blaming the connection")
    func aMissingBackendIsItsOwnSentence() async {
        let record = TodayRecord(store: nil, day: { self.day })

        await record.load()

        guard case let .unavailable(message) = record.status else {
            Issue.record("a build with no backend did not report the day unavailable")
            return
        }
        #expect(message.contains("no backend"))
        #expect(!message.contains("connection"))
    }

    @Test("a second read does not start while the first is in flight")
    func concurrentLoadsAreSerialised() async {
        // The screen's `task` and a pull-to-refresh can both fire, and a stale
        // failure landing after a fresh success would put the error back in
        // front of somebody whose day had just arrived.
        let store = FakeCheckIns()
        store.readHangs = true
        let record = record(store)

        let first = Task { await record.load() }

        // Bounded, because an unbounded wait turns a regression here into a
        // suite that hangs rather than one that fails.
        let deadline = Date().addingTimeInterval(2)
        while store.reads == 0, Date() < deadline {
            await Task.yield()
        }
        #expect(store.reads == 1, "the first read never started")

        await record.load()

        #expect(store.reads == 1, "a second read started while the first was in flight")
        first.cancel()
        await first.value
    }
}
