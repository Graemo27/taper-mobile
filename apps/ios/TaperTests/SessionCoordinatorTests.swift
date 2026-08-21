import Foundation
import Testing
@testable import Taper

/// An auth client that records the order it was asked to do things.
///
/// Order rather than counts, because the rule under test is a sequence: the
/// stored session has to be gone *before* anything reads one.
private final class RecordingAuth: AnonymousAuthClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }

    /// The id a surviving session would report.
    var storedUserID = UUID()
    var freshUserID = UUID()

    func validUserID() async throws -> UUID {
        lock.withLock { _calls.append("read") }
        return storedUserID
    }

    func signInAnonymously() async throws -> UUID {
        lock.withLock { _calls.append("signIn") }
        return freshUserID
    }

    func clearSession() async {
        lock.withLock { _calls.append("clear") }
        storedUserID = freshUserID
    }

    func canRecover(from error: Error) -> Bool { false }
}

/// Covers dropping a stored session before anything reads one.
struct SessionCoordinatorForgetTests {
    @Test("the stored session is gone before the first read, not alongside it")
    func forgettingHappensFirst() async throws {
        // The first version of this ran the sign-out in an unstructured task
        // beside the client's construction, so it raced the first read and
        // whichever won decided the run. Inside the actor there is no race to
        // lose: nothing can ask for a user id until this has happened.
        let auth = RecordingAuth()
        let coordinator = SessionCoordinator(auth: auth, forgetStoredSession: true)

        _ = try await coordinator.userID()

        #expect(auth.calls.first == "clear", "something read a session before it was dropped")
    }

    @Test("it happens once, not on every call")
    func forgettingIsNotRepeated() async throws {
        // Signing out before every request would throw away the session the
        // previous request just established, and every write would be a fresh
        // anonymous user with none of the last one's rows.
        let auth = RecordingAuth()
        let coordinator = SessionCoordinator(auth: auth, forgetStoredSession: true)

        _ = try await coordinator.userID()
        _ = try await coordinator.userID()
        _ = try await coordinator.userID()

        #expect(auth.calls.filter { $0 == "clear" }.count == 1)
    }

    @Test("a run that did not ask keeps the session it has")
    func theOrdinaryLaunchIsUntouched() async throws {
        // The flag is off in every shipped build. A launch that dropped its
        // session would sign somebody out of their own plan on every start.
        let auth = RecordingAuth()
        let coordinator = SessionCoordinator(auth: auth, forgetStoredSession: false)

        _ = try await coordinator.userID()

        #expect(!auth.calls.contains("clear"), "an ordinary launch dropped its session")
        #expect(auth.calls == ["read"])
    }
}
