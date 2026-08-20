import Foundation
import Testing
@testable import Taper

/// A store that does what the test needs and counts what it was asked.
///
/// The two branches worth covering are the ones a real backend cannot be asked
/// to perform on demand: a write that fails, and a second write that must never
/// happen.
private final class FakeStore: TaperPlanWriting, @unchecked Sendable {
    enum Behaviour { case succeed, fail, hang }

    let behaviour: Behaviour

    /// Locked because `save` runs off the main actor while the test reads this
    /// from it. An unsynchronised counter here would make the double-submit
    /// test report a race of its own as a defect in the code under test.
    private let lock = NSLock()
    private var _writes = 0
    var writes: Int { lock.withLock { _writes } }

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

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
            quitDate: nil
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

/// Covers the one write onboarding makes.
@MainActor
struct PlanSubmissionTests {
    @Test("a plan that saves reports saved")
    func aSuccessfulWriteSettles() async {
        let store = FakeStore(.succeed)
        let submission = PlanSubmission(store: store)
        #expect(submission.state == .idle)

        await submission.submit(draft)

        #expect(submission.state == .saved)
        #expect(store.writes == 1)
    }

    @Test("a write that fails says so in words the user can act on")
    func aFailedWriteIsReported() async {
        // The branch no screenshot catches. A save that fails quietly leaves
        // someone believing the app is tracking a plan it never wrote down.
        let submission = PlanSubmission(store: FakeStore(.fail))

        await submission.submit(draft)

        guard case let .failed(message) = submission.state else {
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
        let submission = PlanSubmission(store: nil)

        await submission.submit(draft)

        guard case let .failed(message) = submission.state else {
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
        let submission = PlanSubmission(store: store)

        let first = Task { await submission.submit(draft) }
        // Wait for the write itself, not for the state that precedes it.
        // `.saving` is set before `save` is entered, so spinning on the state
        // asserts before the first write has happened and reads zero.
        while store.writes == 0 { await Task.yield() }
        #expect(submission.state == .saving)

        await submission.submit(draft)

        #expect(store.writes == 1, "a second tap started a second write")
        first.cancel()
    }

    @Test("a plan already saved is not written again")
    func submittingTwiceOverWritesOnce() async {
        let store = FakeStore(.succeed)
        let submission = PlanSubmission(store: store)

        await submission.submit(draft)
        await submission.submit(draft)

        #expect(store.writes == 1)
        #expect(submission.state == .saved)
    }

    @Test("a failure can be cleared so the plan can be offered again")
    func aFailureIsRecoverable() async {
        // Assert the exit from a state, not only the entry. A failure with no
        // way out is a dead end wearing an error message.
        let submission = PlanSubmission(store: FakeStore(.fail))
        await submission.submit(draft)

        submission.dismissFailure()

        #expect(submission.state == .idle)
    }
}
