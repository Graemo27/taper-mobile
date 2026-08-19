import SwiftUI

/// Entry point.
///
/// Deliberately bare. The Food Pad UI it used to compose is gone and Taper's is
/// not built yet, so this launches, signs in, and says so — nothing more. It is
/// a placeholder with a job: proving the shell underneath still works before any
/// screen is written on top of it.
@main
struct TaperApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchStateView()
                .preferredColorScheme(.light)
        }
    }
}

/// Reports whether the app has a backend and whether a session was obtained.
///
/// The backend marker is carried over from the app this replaced, and is the one
/// piece of that root worth keeping. A configured app and an app whose backend is
/// unreachable used to render identically, so the difference was not observable —
/// and an app that launched with no configuration at all once shipped, caught
/// only by running it on a phone. Stating it on screen means the failure cannot
/// hide again while there are no other screens to notice it.
private struct LaunchStateView: View {
    @State private var session: SessionState = .connecting

    private enum SessionState {
        case connecting
        case signedIn(UUID)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Taper")
                .font(.largeTitle.weight(.medium))

            Text("No screens yet — the Food Pad UI has been removed and Taper's is not built.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Label(
                AppConfiguration.backend == nil ? "No backend configured" : "Backend configured",
                systemImage: AppConfiguration.backend == nil ? "xmark.circle" : "checkmark.circle"
            )
            .accessibilityIdentifier(
                AppConfiguration.backend == nil ? "app.backend-missing" : "app.backend-configured"
            )

            switch session {
            case .connecting:
                Label("Signing in…", systemImage: "clock")
            case let .signedIn(id):
                Label("Signed in anonymously", systemImage: "person.fill.checkmark")
                    .accessibilityIdentifier("app.session-active")
                Text(id.uuidString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("app.session-failed")
            }

            Spacer()
        }
        .font(.body)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await signIn() }
    }

    private func signIn() async {
        guard let backend = AppConfiguration.backend else {
            session = .failed("Run Scripts/write-config.sh, then rebuild.")
            return
        }
        let client = AppSupabase.make(url: backend.url, publishableKey: backend.publishableKey)
        do {
            session = .signedIn(try await SessionCoordinator(
                auth: SupabaseAnonymousAuth(client: client)
            ).userID())
        } catch {
            session = .failed("Sign-in failed: \(error.localizedDescription)")
        }
    }
}
