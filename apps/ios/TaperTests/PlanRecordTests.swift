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
    /// Waits for cancellation and then throws the way a cancelled URL request
    /// does. `CancellationError` and `URLError.cancelled` reach the catch by
    /// different routes, and only one of them is a pattern.
    var readCancelledInFlight = false
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

    /// Shared with `FakePad`, so the order of the two writes can be asserted.
    let order: OrderLog

    init(_ behaviour: Behaviour = .succeed, order: OrderLog = OrderLog()) {
        self.behaviour = behaviour
        self.order = order
    }

    func currentPlan() async throws -> StoredTaperPlan? {
        lock.withLock { _reads += 1 }
        if readCancelledInFlight {
            while !Task.isCancelled { await Task.yield() }
            throw URLError(.cancelled)
        }
        if readHangs { try await Task.sleep(for: .seconds(30)) }
        if readFails { throw URLError(.notConnectedToInternet) }
        return existing
    }

    func save(_ draft: TaperPlanDraft) async throws -> StoredTaperPlan {
        order.record("plan")
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

/// A pad that records what it was asked to seed, and can refuse.
///
/// Shares an order log with `FakeStore`, because the property under test is not
/// what each of them was told but which of them was told first — and that is
/// invisible to two fakes counting separately.
private final class FakePad: PadKeyStoring, @unchecked Sendable {
    let behaviour: FakeStore.Behaviour
    let order: OrderLog

    private let lock = NSLock()
    private var _seeded: [[PadKey]] = []
    /// Every seed it was asked for, in order. A list rather than a count, so a
    /// second seed carrying different keys is distinguishable from a repeat.
    var seeded: [[PadKey]] { lock.withLock { _seeded } }

    init(_ behaviour: FakeStore.Behaviour = .succeed, order: OrderLog = OrderLog()) {
        self.behaviour = behaviour
        self.order = order
    }

    func seed(_ keys: [PadKey]) async throws -> [StoredPadKey] {
        order.record("pad")
        lock.withLock { _seeded.append(keys) }
        if behaviour == .fail { throw URLError(.notConnectedToInternet) }
        return keys.enumerated().map { index, key in
            StoredPadKey(id: index + 1, form: key.form, label: key.label,
                         mg: key.mg, position: key.position, ndc: nil)
        }
    }

    func currentKeys() async throws -> [StoredPadKey] { [] }
}

/// Which writes happened, in the order they happened.
private final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _steps: [String] = []
    var steps: [String] { lock.withLock { _steps } }
    func record(_ step: String) { lock.withLock { _steps.append(step) } }
}

private let draft = TaperPlanDraft(
    startingCapMg: 18,
    currentCapMg: 18,
    capEffectiveFrom: Date(timeIntervalSince1970: 1_760_000_000),
    quitDate: nil,
    firstUseMinutes: 20,
    sickInBed: true
)


/// The tap at the end of onboarding: the row to write and the pad to seed.
private let run = CompletedRun(
    draft: draft,
    padKeys: [PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0)]
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
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)

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
        let record = PlanRecord(store: FakeStore(), pad: FakePad())

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
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)

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
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)
        await record.load()

        store.readFails = false
        await record.load()

        #expect(record.status.isPresent)
        #expect(store.readCount == 2)
    }


    @Test("a check abandoned mid-flight is not reported as a connection failure")
    func cancellingTheCheckSaysNothing() async {
        // The launch check runs in a view's `task`, so it is cancelled exactly
        // when the view goes away. Reporting that as `unknown` would put the
        // could-not-check screen in front of somebody whose connection was
        // fine — and that screen's whole job is to be believed.
        let store = FakeStore()
        store.existing = existingPlan
        store.readHangs = true
        let record = PlanRecord(store: store, pad: FakePad())

        let task = Task { await record.load() }
        let deadline = Date().addingTimeInterval(2)
        while store.readCount == 0, Date() < deadline {
            await Task.yield()
        }
        #expect(store.readCount == 1, "the read never started")
        task.cancel()
        await task.value

        #expect(record.status == .checking, "an abandoned check reported something")
    }

    @Test("a check whose request is cancelled in flight is not reported either")
    func aCancelledCheckRequestSaysNothing() async {
        // The route a `catch is CancellationError` misses: a request already
        // in flight is reported as `URLError.cancelled`, which is an ordinary
        // error until the task's own flag is consulted. It is the reason the
        // guard asks the flag instead of matching a type.
        let store = FakeStore()
        store.existing = existingPlan
        store.readCancelledInFlight = true
        let record = PlanRecord(store: store, pad: FakePad())

        let task = Task { await record.load() }
        let deadline = Date().addingTimeInterval(2)
        while store.readCount == 0, Date() < deadline {
            await Task.yield()
        }
        #expect(store.readCount == 1, "the read never started")
        task.cancel()
        await task.value

        #expect(record.status == .checking, "a cancelled request was reported as a failure")
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
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)

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
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)
        await record.load()

        await record.submit(run)

        #expect(record.status.isPresent)
        #expect(store.readCount == 1, "the plan was re-read after being written")
    }

    // MARK: - Writing

    @Test("a plan that saves reports saved")
    func aSuccessfulWriteSettles() async {
        let store = FakeStore(.succeed)
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)
        await record.load()
        #expect(record.status == .absent)

        await record.submit(run)

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

    @Test("finishing onboarding puts the pad on the server too")
    func theTapThatSavesAPlanAlsoSeedsThePad() async {
        // Without this the app saves a plan and lands somebody on a home screen
        // with nothing to tap — and, because a saved plan routes the next
        // launch past onboarding, nothing ever asks the questions again.
        let pad = FakePad()
        let record = PlanRecord(store: FakeStore(), pad: pad)

        await record.submit(run)

        #expect(pad.seeded == [run.padKeys], "the pad was not seeded from the run")
    }

    @Test("the pad is written before the plan, because that is the order that recovers")
    func thePadGoesFirst() async {
        // Not an arbitrary sequence. Seeding is idempotent, so a pad written
        // without a plan is a state the next run walks straight through:
        // onboarding finds no plan, asks again, seeds nothing new, saves. The
        // other order strands people on a home screen with an empty pad and no
        // path back to the questions.
        let order = OrderLog()
        let record = PlanRecord(store: FakeStore(order: order), pad: FakePad(order: order))

        await record.submit(run)

        #expect(order.steps == ["pad", "plan"])
    }

    @Test("a pad that cannot be written stops the plan being written")
    func aFailedSeedDoesNotSaveThePlan() async {
        // The half-finished write this ordering is chosen to avoid. Saving the
        // plan anyway would leave the unrecoverable state: a plan on file, an
        // empty pad, and onboarding never offered again.
        let store = FakeStore()
        let record = PlanRecord(store: store, pad: FakePad(.fail))

        await record.submit(run)

        #expect(store.writes == 0, "the plan was saved on top of a pad that failed")
        guard case let .saveFailed(message) = record.status else {
            Issue.record("a failed seed did not reach the failed state")
            return
        }
        #expect(message.contains("try again"))
    }

    @Test("a plan that fails leaves the pad in place for the retry")
    func aFailedPlanKeepsTheSeededPad() async {
        // The recovery this buys. The pad is already on the server, so the
        // second attempt seeds nothing new and only has the plan left to write.
        let pad = FakePad()
        let record = PlanRecord(store: FakeStore(.fail), pad: pad)

        await record.submit(run)

        #expect(pad.seeded == [run.padKeys])
        #expect(!record.status.isPresent)
    }

    @Test("a write that fails says so in words the user can act on")
    func aFailedWriteIsReported() async {
        // The branch no screenshot catches. A save that fails quietly leaves
        // someone believing the app is tracking a plan it never wrote down.
        let record = PlanRecord(store: FakeStore(.fail), pad: FakePad())

        await record.submit(run)

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

        await record.submit(run)

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
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)

        let first = Task { await record.submit(run) }

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

        await record.submit(run)

        #expect(store.writes == 1, "a second tap started a second write")
        first.cancel()
        // Let the cancelled write finish unwinding before the test ends,
        // rather than leaving it running into whatever runs next.
        await first.value
    }

    @Test("a plan already saved is not written again")
    func submittingTwiceOverWritesOnce() async {
        let store = FakeStore(.succeed)
        let pad = FakePad()
        let record = PlanRecord(store: store, pad: pad)

        await record.submit(run)
        await record.submit(run)

        #expect(store.writes == 1)
        #expect(record.status.isPresent)
    }

    @Test("a failure can be cleared so the plan can be offered again")
    func aFailureIsRecoverable() async {
        // Assert the exit from a state, not only the entry. A failure with no
        // way out is a dead end wearing an error message.
        let record = PlanRecord(store: FakeStore(.fail), pad: FakePad())
        await record.submit(run)

        record.dismissFailure()

        #expect(record.status == .absent)
    }
}
