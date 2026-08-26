import Foundation
import Testing
@testable import Taper

/// A log that records what it was asked to write, and can refuse or stall.
private final class FakeLog: CheckInWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()

    private struct State {
        var logged: [CheckInDraft] = []
        var fails = false
        var holds = false
    }

    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    var holds: Bool {
        get { lock.withLock { state.holds } }
        set { lock.withLock { state.holds = newValue } }
    }
    var logged: [CheckInDraft] { lock.withLock { state.logged } }

    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn {
        let shouldFail = lock.withLock {
            state.logged.append(draft)
            return state.fails
        }
        while holds { await Task.yield() }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return StoredCheckIn(
            id: 1, ledger: draft.ledger, label: draft.label, form: draft.form,
            mg: draft.mg, quantity: draft.quantity,
            loggedOn: "2026-08-26", createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private func key(_ form: PadForm, _ label: String, mg: Double, position: Int = 0) -> StoredPadKey {
    StoredPadKey(id: position + 1, form: form, label: label,
                 mg: mg, position: position, ndc: nil)
}

/// Where a task reports back to the test, so a wait can end on a decision
/// rather than on a duration.
@MainActor
private final class Outcome {
    var decided = false
    var value: StoredCheckIn?
}

/// Covers the craving screen's state: what it offers, and what getting through
/// one records.
@MainActor
struct CravingRecordTests {
    @Test("it offers something that works on the timescale of a craving")
    func aPatchIsNotAnAnswerToAMoment() {
        // A patch holds a floor; a lozenge answers a moment. The board's card
        // says "This is what it's for", which is only true of the second kind.
        let pad = Pad(keys: [
            key(.patch, "Patch", mg: 21, position: 0),
            key(.lozenge, "Lozenge", mg: 4, position: 1),
        ])

        #expect(CravingRecord.suggestion(from: pad)?.form == .lozenge)
    }

    @Test("a pad with nothing fast-acting offers nothing rather than a patch")
    func theAbsenceIsHonest() {
        // Somebody on a patch alone, or quitting cold. Inventing a suggestion
        // out of a patch would be advice that does not work when they need it.
        #expect(CravingRecord.suggestion(from: Pad(keys: [
            key(.patch, "Patch", mg: 21),
        ])) == nil)

        #expect(CravingRecord.suggestion(from: Pad(keys: [])) == nil)
    }

    @Test("what is being quit is never offered as the answer to wanting it")
    func theSourceLedgerIsNotASuggestion() {
        // The pad holds both ledgers. Reaching into the wrong one would hand
        // somebody mid-craving the pouches they are quitting.
        let pad = Pad(keys: [
            key(.pouch, "Pouches", mg: 6, position: 0),
            key(.vape, "Vape", mg: 2, position: 1),
        ])

        #expect(CravingRecord.suggestion(from: pad) == nil,
                "the craving screen offered a source")
    }

    @Test("a craving that passed is recorded as costing nothing")
    func gettingThroughOneIsNotADose() async {
        let log = FakeLog()
        let record = CravingRecord(store: log)

        #expect(await record.itPassed() != nil)

        let written = try? #require(log.logged.first)
        #expect(written?.mg == 0, "an urge was recorded as a dose")
        #expect(written?.padKeyID == nil, "an urge cited a key nobody pressed")
        #expect(written?.label == CheckInDraft.urgeLabel)
        #expect(written?.isUrge == true)
    }

    @Test("it is filed where it cannot count against the day")
    func anUrgeIsNotSomethingUsed() async {
        // The source ledger is what the cap counts. An urge landing there would
        // make getting through a craving look like giving in to one.
        let log = FakeLog()
        _ = await CravingRecord(store: log).itPassed()

        #expect(log.logged.first?.ledger == .treatment)
    }

    @Test("a failure says the thing that mattered already happened")
    func theRecordIsWhatFailed() async {
        // Somebody reading this is mid-craving. "Try again" would ask them to
        // do the app's job at the worst possible moment; what failed is the
        // note, not the getting through.
        let log = FakeLog()
        log.fails = true
        let record = CravingRecord(store: log)

        #expect(await record.itPassed() == nil)
        #expect(record.status == .failed("That didn't save. It still counts."))
    }

    @Test("one craving is counted once, however many times it is tapped")
    func aSecondTapWhileCountingIsRefused() async {
        let log = FakeLog()
        log.holds = true
        let record = CravingRecord(store: log)

        let first = Task { await record.itPassed() }
        let deadline = Date().addingTimeInterval(3)
        while log.logged.isEmpty, Date() < deadline { await Task.yield() }
        #expect(log.logged.count == 1, "the first write never started")

        // Started rather than awaited: with the guard missing this reaches the
        // held write and sits there, and a test that hangs teaches nothing.
        //
        // The wait ends on whichever answer arrives — refused, so the task
        // finishes without touching the log, or accepted, so the log sees a
        // second. The deadline is computed *once*: the first draft of this
        // recomputed `Date().addingTimeInterval` inside the condition, which is
        // always in the future, and the suite ran until it was killed.
        let outcome = Outcome()
        let second = Task { @MainActor in
            outcome.value = await record.itPassed()
            outcome.decided = true
        }
        let secondDeadline = Date().addingTimeInterval(3)
        while !outcome.decided, log.logged.count < 2, Date() < secondDeadline {
            await Task.yield()
        }
        #expect(outcome.decided, "the second tap reached the log instead of being refused")

        log.holds = false
        _ = await first.value
        _ = await second.value

        #expect(log.logged.count == 1, "one craving was counted twice")
    }

    @Test("a build with no backend says so rather than failing quietly")
    func nothingToCountInto() async {
        let record = CravingRecord(store: nil)

        #expect(await record.itPassed() == nil)
        #expect(record.status == .failed(CravingRecord.noBackend))
    }
}
