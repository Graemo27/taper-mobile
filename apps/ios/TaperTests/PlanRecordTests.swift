import Foundation
import Testing
@testable import Taper

/// A store that does what the test needs and counts what it was asked.
///
/// The two branches worth covering are the ones a real backend cannot be asked
/// to perform on demand: a write that fails, and a second write that must never
/// happen.
private final class FakeStore: TaperPlanStoring, @unchecked Sendable {
    enum Behaviour { case succeed, fail, hang }

    let behaviour: Behaviour
    /// What a read finds. Separate from `behaviour`, which governs writes — a
    /// store that fails to save and a store that fails to look are different
    /// tests.
    var existing: StoredTaperPlan?
    var readFails = false
    /// Holds a read open, so a second one can be attempted while the first is
    /// still in flight.
    var readHangs = false

    /// Locked because `save` runs off the main actor while the test reads this
    /// from it. An unsynchronised counter here would make the double-submit
    /// test report a race of its own as a defect in the code under test.
    private let lock = NSLock()
    private var _writes = 0
    private var _reads = 0
    var writes: Int { lock.withLock { _writes } }
    var readCount: Int { lock.withLock { _reads } }

    init(_ behaviour: Behaviour = .succeed) { self.behaviour = behaviour }

    func currentPlan() async throws -> StoredTaperPlan? {
        lock.withLock { _reads += 1 }
        if readHangs { try await Task.sleep(for: .seconds(30)) }
        if readFails { throw URLError(.notConnectedToInternet) }
        return existing
    }

    func save(_ draft: TaperPlanDraft) async throws -> StoredTaperPlan {
        lock.withLock { _writes += 1 }
        switch behaviour {
        case .fail:
            throw URLError(.notConnectedToInternet)
        case .hang:
            // Long enough to still be in flight while the test asserts, and
            // cancelled with the task rather than left running.
            try await Task.sleep(for: .seconds(30))
        case .succeed:
            break
        }
        return StoredTaperPlan(
            id: 1,
            startingCapMg: draft.startingCapMg,
            currentCapMg: draft.currentCapMg,
            capEffectiveFrom: "2025-10-09",
            quitDate: nil,
            firstUseMinutes: draft.firstUseMinutes,
            sickInBed: draft.sickInBed
        )
    }
}

private let draft = TaperPlanDraft(
    startingCapMg: 18,
    currentCapMg: 18,
    capEffectiveFrom: Date(timeIntervalSince1970: 1_760_000_000),
    quitDate: nil,
    firstUseMinutes: 20,
    sickInBed: true
)


private let existingPlan = StoredTaperPlan(
    id: 7,
    startingCapMg: 18,
    currentCapMg: 18,
    capEffectiveFrom: "2025-10-09",
    quitDate: nil,
    firstUseMinutes: 20,
    sickInBed: true
)

/// What `FakeStore.save` returns for `draft`. A different id from
/// `existingPlan` on purpose: the home screen is drawn from whichever of the
/// two the status is carrying, so a write that left the read's plan in place
/// has to be a visible failure rather than an equal value.
private let writtenPlan = StoredTaperPlan(
    id: 1,
    startingCapMg: 18,
    currentCapMg: 18,
    capEffectiveFrom: "2025-10-09",
    quitDate: nil,
    firstUseMinutes: 20,
    sickInBed: true
)

/// Covers the app's record of the plan: finding it, and writing it.
@MainActor
struct PlanRecordTests {

    // MARK: - Finding a plan already on file

    @Test("a returning user is not asked the questions again")
    func anExistingPlanIsFound() async {
        // The gap this closes: the app wrote a plan and had no way to discover
        // it existed, so every launch replayed twelve questions at someone
        // whose plan was already on the server — then overwrote it.
        let store = FakeStore()
        store.existing = existingPlan
        let record = PlanRecord(store: store)

        await record.load()

        // The exact row, not merely "present". Everything the home screen
        // shows is computed from the plan this status carries, so a read that
        // reported presence while carrying a synthesized or stale plan would
        // draw a confident screen full of the wrong numbers.
        guard case let .present(found) = record.status else {
            Issue.record("a plan on file was not reported as present")
            return
        }
        #expect(found == existingPlan)
    }

    @Test("someone with no plan gets the questions")
    func noPlanMeansOnboarding() async {
        let record = PlanRecord(store: FakeStore())

        await record.load()

        #expect(record.status == .absent)
    }

    @Test("a check that fails is not read as having no plan")
    func aFailedCheckIsNotAnAbsence() async {
        // The distinction the whole `unknown` case exists for. Falling through
        // to `absent` would take twelve answers from a returning user and then
        // write over the plan they were never shown — a wrong guess that costs
        // more than saying so.
        let store = FakeStore()
        store.existing = existingPlan
        store.readFails = true
        let record = PlanRecord(store: store)

        await record.load()

        guard case let .unknown(message) = record.status else {
            Issue.record("a failed check did not reach the unknown state")
            return
        }
        #expect(record.status != .absent)
        #expect(message.contains("try again"))
        #expect(!message.contains("URLError"))
    }

    @Test("a build with no backend cannot check either, and says so")
    func aMissingBackendCannotCheck() async {
        let record = PlanRecord(store: nil)

        await record.load()

        guard case let .unknown(message) = record.status else {
            Issue.record("a build with no backend did not report an unknown plan")
            return
        }
        #expect(message.contains("no backend"))
        #expect(!message.contains("connection"))
    }

    @Test("a failed check can be retried without restarting the app")
    func aFailedCheckIsRecoverable() async {
        // Assert the exit from a state, not only the entry.
        let store = FakeStore()
        store.existing = existingPlan
        store.readFails = true
        let record = PlanRecord(store: store)
        await record.load()

        store.readFails = false
        await record.load()

        #expect(record.status.isPresent)
        #expect(store.readCount == 2)
    }


    @Test("a second lookup does not start while the first is in flight")
    func concurrentLoadsAreSerialised() async {
        // One tap on Try again issues two reads: the retry starts a load, which
        // sets `checking`, which renders the looking-for-it screen, whose task
        // starts another. Whichever finishes last wins — so a stale failure can
        // put the error screen back in front of someone whose plan was found.
        let store = FakeStore()
        store.existing = existingPlan
        store.readHangs = true
        let record = PlanRecord(store: store)

        let first = Task { await record.load() }

        // Bounded, because the condition being waited on is what a regression
        // here would break.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.readCount == 0 {
            guard ContinuousClock.now < deadline else {
                Issue.record("the first load never reached the store")
                first.cancel()
                return
            }
            await Task.yield()
        }

        await record.load()

        #expect(store.readCount == 1, "a second lookup started while the first was in flight")
        first.cancel()
        await first.value
    }

    @Test("a plan just written needs no second look")
    func savingDoesNotRequireAReread() async {
        let store = FakeStore()
        let record = PlanRecord(store: store)
        await record.load()

        await record.submit(draft)

        #expect(record.status.isPresent)
        #expect(store.readCount == 1, "the plan was re-read after being written")
    }

    // MARK: - Writing

    @Test("a plan that saves reports saved")
    func aSuccessfulWriteSettles() async {
        let store = FakeStore(.succeed)
        let record = PlanRecord(store: store)
        await record.load()
        #expect(record.status == .absent)

        await record.submit(draft)

        // The row the store returned, not the draft that went in. The two are
        // different types for a reason — the server assigns the id, and the
        // screen the user lands on is drawn from what came back.
        guard case let .present(saved) = record.status else {
            Issue.record("a successful write did not reach the present state")
            return
        }
        #expect(saved == writtenPlan)
        #expect(store.writes == 1)
    }

    @Test("a write that fails says so in words the user can act on")
    func aFailedWriteIsReported() async {
        // The branch no screenshot catches. A save that fails quietly leaves
        // someone believing the app is tracking a plan it never wrote down.
        let record = PlanRecord(store: FakeStore(.fail))

        await record.submit(draft)

        guard case let .saveFailed(message) = record.status else {
            Issue.record("a failed write did not reach the failed state")
            return
        }
        #expect(message.contains("try again"))
        // Never the underlying error: a user cannot act on a URLError, and one
        // on screen reads as the app breaking rather than as something to retry.
        #expect(!message.contains("URLError"))
        #expect(!message.lowercased().contains("nsurlerror"))
    }

    @Test("a build with no backend says that, rather than blaming the network")
    func aMissingBackendIsItsOwnFailure() async {
        // This project shipped an app configured only while a test drove it,
        // and the whole cost was that an unconfigured build and an unreachable
        // one looked the same. They do not look the same here.
        let record = PlanRecord(store: nil)

        await record.submit(draft)

        guard case let .saveFailed(message) = record.status else {
            Issue.record("a build with no backend did not report a failure")
            return
        }
        #expect(message.contains("no backend"))
        #expect(!message.contains("connection"))
    }

    @Test("a second tap while the first is in flight does not write twice")
    func doubleSubmitWritesOnce() async {
        // The CTA is disabled while saving, but that is a rendering decision.
        // Two taps landing either side of the first render would otherwise
        // write twice, against a table that holds one plan per person.
        let store = FakeStore(.hang)
        let record = PlanRecord(store: store)

        let first = Task { await record.submit(draft) }

        // Wait for the write itself, not for the state that precedes it.
        // `.saving` is set before `save` is entered, so spinning on the state
        // asserts before the first write has happened and reads zero.
        //
        // Bounded, because the condition being waited on is exactly what a
        // regression here would break: a submit that never reaches the store
        // would spin forever, and a suite that hangs reports nothing at all.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.writes == 0 {
            guard ContinuousClock.now < deadline else {
                Issue.record("the first submit never reached the store")
                first.cancel()
                return
            }
            await Task.yield()
        }
        #expect(record.status == .saving)

        await record.submit(draft)

        #expect(store.writes == 1, "a second tap started a second write")
        first.cancel()
        // Let the cancelled write finish unwinding before the test ends,
        // rather than leaving it running into whatever runs next.
        await first.value
    }

    @Test("a plan already saved is not written again")
    func submittingTwiceOverWritesOnce() async {
        let store = FakeStore(.succeed)
        let record = PlanRecord(store: store)

        await record.submit(draft)
        await record.submit(draft)

        #expect(store.writes == 1)
        #expect(record.status.isPresent)
    }

    @Test("a failure can be cleared so the plan can be offered again")
    func aFailureIsRecoverable() async {
        // Assert the exit from a state, not only the entry. A failure with no
        // way out is a dead end wearing an error message.
        let record = PlanRecord(store: FakeStore(.fail))
        await record.submit(draft)

        record.dismissFailure()

        #expect(record.status == .absent)
    }
}
