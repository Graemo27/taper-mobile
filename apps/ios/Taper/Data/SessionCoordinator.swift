import Foundation
import Supabase

/// Builds the app's one Supabase client, routed through `NetworkSession.live()`
/// so launch-argument faults reach Supabase traffic too.
enum AppSupabase {
    static func make(url: URL, publishableKey: String) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: .init(global: .init(session: NetworkSession.live()))
        )
    }
}

/// The slice of auth the coordinator needs: a current user id, a fresh
/// anonymous sign-in, and the judgement call of which errors mean
/// "sign in again" rather than "give up".
protocol AnonymousAuthClient: Sendable {
    func validUserID() async throws -> UUID
    func signInAnonymously() async throws -> UUID
    func clearSession() async
    func canRecover(from error: Error) -> Bool
}

/// Recovery is deliberately narrow: a missing session, or a 400 naming an
/// invalid refresh token. Anything else propagates.
struct SupabaseAnonymousAuth: AnonymousAuthClient {
    let client: SupabaseClient

    func validUserID() async throws -> UUID { try await client.auth.session.user.id }
    func signInAnonymously() async throws -> UUID {
        try await client.auth.signInAnonymously().user.id
    }
    func clearSession() async { try? await client.auth.signOut(scope: .local) }

    func canRecover(from error: Error) -> Bool {
        guard let error = error as? AuthError else { return false }
        switch error {
        case .sessionMissing:
            return true
        case let .api(message, code, _, response):
            return response.statusCode == 400
                && (code == .refreshTokenNotFound
                    || message.localizedCaseInsensitiveContains("invalid refresh token"))
        default:
            return false
        }
    }
}

/// Runs work as a signed-in anonymous user, healing a dead session once per
/// call and coalescing concurrent sign-ins into a single request.
actor SessionCoordinator {
    private let auth: any AnonymousAuthClient
    private var pendingSignIn: Task<UUID, Error>?
    /// Whether the stored session still has to be dropped.
    ///
    /// The decision lives in the actor rather than beside the client, because
    /// the actor is what orders it: dropping the session in an unstructured
    /// task alongside construction races the first read, and the run that
    /// reads first wins. Here, nothing can ask for a user id before it has
    /// happened.
    private var mustForgetStoredSession: Bool

    init(
        auth: any AnonymousAuthClient,
        forgetStoredSession: Bool = ProcessInfo.processInfo.arguments
            .contains("-TaperForgetSession")
    ) {
        self.auth = auth
        mustForgetStoredSession = forgetStoredSession
    }

    func userID() async throws -> UUID {
        // Once, and before anything reads a session. The same shape as
        // `-TaperForgetAge`: it *clears* device state and supplies none, so a
        // run that uses it still signs in and still writes for real.
        //
        // It exists because a simulator keeps its session across launches while
        // `supabase db reset --local` takes `auth.users` with it. The token
        // still verifies — it is signed — so nothing looks wrong until the
        // first insert fails a foreign key against a user the database has
        // never heard of, and the screen blames the connection for it.
        if mustForgetStoredSession {
            mustForgetStoredSession = false
            await auth.clearSession()
        }
        do { return try await auth.validUserID() }
        catch where auth.canRecover(from: error) {
            return try await freshUserID()
        }
    }

    func authenticated<T: Sendable>(
        _ operation: @Sendable (UUID) async throws -> T
    ) async throws -> T {
        let current = try await userID()
        do { return try await operation(current) }
        catch where auth.canRecover(from: error) {
            return try await operation(freshUserID())
        }
    }

    private func freshUserID() async throws -> UUID {
        if let pendingSignIn { return try await pendingSignIn.value }
        let task = Task {
            await auth.clearSession()
            return try await auth.signInAnonymously()
        }
        pendingSignIn = task
        defer { pendingSignIn = nil }
        return try await task.value
    }
}
