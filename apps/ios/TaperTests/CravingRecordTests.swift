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
        #expect(record.status == .failed(.count, "That didn't save. It still counts."))
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

    @Test("one craving is counted once, however long the screen stays open")
    func aSecondTapAfterASuccessIsRefused() async {
        // The screen does not close itself the instant the write lands, so the
        // button outlives the row it wrote. Re-enabling it would file the same
        // craving twice — the first draft returned to `resting` on success and
        // did exactly that.
        let log = FakeLog()
        let record = CravingRecord(store: log)

        #expect(await record.itPassed() != nil)
        #expect(record.status == .logged(.count))
        #expect(await record.itPassed() == nil, "the same craving was offered a second row")
        #expect(log.logged.count == 1, "one craving was counted twice")
    }

    @Test("a write that did not land can still be tried again")
    func aFailureIsNotTerminal() async {
        // The other half of the rule above: `counted` closes the button because
        // a row exists, and a failure means one does not.
        let log = FakeLog()
        log.fails = true
        let record = CravingRecord(store: log)
        _ = await record.itPassed()

        log.fails = false
        #expect(await record.itPassed() != nil, "a failed count could not be retried")
    }

    @Test("taking what the screen suggested logs it the way the pad would")
    func theSuggestionIsARealDose() async {
        // Written through its own store rather than the pad's selection: that
        // selection is a count somebody may be halfway through tapping out on
        // another tab, and borrowing it would either clobber it or send it.
        let log = FakeLog()
        let record = CravingRecord(store: log)
        let lozenge = key(.lozenge, "Lozenge", mg: 4)

        #expect(await record.take(lozenge) != nil)

        let written = try? #require(log.logged.first)
        #expect(written?.padKeyID == lozenge.id, "the dose cited no key")
        #expect(written?.mg == 4)
        #expect(written?.ledger == .treatment)
        #expect(written?.isUrge == false, "a dose was recorded as a craving got through")
    }

    @Test("one screen writes one row, whichever button wrote it")
    func aTakeAndACountCannotBothLand() async {
        // Both end the screen. A count landing on top of a take would file the
        // same craving as a dose and as a pass at once.
        let log = FakeLog()
        let record = CravingRecord(store: log)

        #expect(await record.take(key(.lozenge, "Lozenge", mg: 4)) != nil)
        #expect(await record.itPassed() == nil, "a spent screen counted a craving as well")
        #expect(log.logged.count == 1)
    }

    @Test("a dose that did not record asks to be tried again")
    func aFailedDoseIsNotAFailedCount() async {
        // The other failure says the thing that mattered already happened. This
        // one cannot: a dose is a real milligram against a real cap, and a log
        // that quietly drops it is a cap that lies.
        let log = FakeLog()
        log.fails = true
        let record = CravingRecord(store: log)

        _ = await record.take(key(.lozenge, "Lozenge", mg: 4))

        #expect(record.status == .failed(.take, "Couldn't log that. Try again."))
    }

    @Test("what to put away is named off what they are actually quitting")
    func theTinIsNotEverybodys() {
        // The board says "Put the tin away", which is true of a pouch and of
        // nobody else. Telling a smoker mid-craving to put a tin away is the
        // app not knowing who it is talking to.
        func title(_ keys: [StoredPadKey]) -> String {
            CravingRecord.putAwayTitle(for: Pad(keys: keys))
        }

        #expect(title([key(.pouch, "Pouches", mg: 6)]) == "Put the tin away")
        #expect(title([key(.cigarette, "Cigarettes", mg: 1)]) == "Put the pack away")
        #expect(title([key(.vape, "Vape", mg: 2)]) == "Put the vape away")

        // Naming one of two would be a guess about which they are reaching for,
        // and so would naming a source the user typed themselves.
        let neutral = "Put it out of reach"
        #expect(title([
            key(.pouch, "Pouches", mg: 6, position: 0),
            key(.cigarette, "Cigarettes", mg: 1, position: 1),
        ]) == neutral)
        #expect(title([key(.other, "Shisha", mg: 3)]) == neutral)
        #expect(title([key(.lozenge, "Lozenge", mg: 4)]) == neutral,
                "a treatment was named as the thing to get away from")
        #expect(title([]) == neutral)
    }

    @Test("a write in flight is visible, so nothing offers a way off the screen")
    func theScreenSaysWhenItIsMidWrite() async {
        // What both exits are guarded on. The write outlives the cover — it is
        // unstructured on purpose — so a screen dismissed mid-write lets a
        // second one be opened and a second row written for one craving.
        let log = FakeLog()
        log.holds = true
        let record = CravingRecord(store: log)

        let writing = Task { await record.itPassed() }
        let deadline = Date().addingTimeInterval(3)
        while log.logged.isEmpty, Date() < deadline { await Task.yield() }
        #expect(record.isWriting, "a write was in flight and the screen did not say so")

        log.holds = false
        _ = await writing.value
        #expect(record.isWriting == false, "the screen held itself shut after its row landed")
    }

    @Test("a build with no backend says so rather than failing quietly")
    func nothingToCountInto() async {
        let record = CravingRecord(store: nil)

        #expect(await record.itPassed() == nil)
        #expect(record.status == .failed(.count, CravingRecord.noBackend))
    }
}
