import Foundation
import Supabase

enum AppSupabase {
    static func make(url: URL, publishableKey: String) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: .init(global: .init(session: NetworkSession.live()))
        )
    }
}

protocol AnonymousAuthClient: Sendable {
    func validUserID() async throws -> UUID
    func signInAnonymously() async throws -> UUID
    func clearSession() async
    func canRecover(from error: Error) -> Bool
}

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

actor SessionCoordinator {
    private let auth: any AnonymousAuthClient
    private var pendingSignIn: Task<UUID, Error>?

    init(auth: any AnonymousAuthClient) { self.auth = auth }

    func userID() async throws -> UUID {
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
