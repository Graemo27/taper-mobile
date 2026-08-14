import Foundation

/// Where the app learns which backend to talk to.
///
/// This existed only as `ProcessInfo.processInfo.environment` lookups repeated
/// at six composition sites. Nothing outside XCUITest ever set those variables,
/// so the app was configured while a test drove it and unconfigured the moment
/// a person tapped the icon — every screen reaching Supabase failed, worded as
/// though the network were down. The values now also reach a build through
/// `Info.plist`, which is the native equivalent of Expo inlining `EXPO_PUBLIC_*`
/// into the JS bundle.
enum AppConfiguration {
    struct Backend: Equatable {
        let url: URL
        let publishableKey: String
    }

    static let backend = resolve(
        environment: ProcessInfo.processInfo.environment,
        bundle: Bundle.main.infoDictionary ?? [:]
    )

    /// The environment wins over the bundle, so a test can still point a build
    /// at a different project without rebuilding it. Both are checked because
    /// only one of them is ever populated at a time.
    static func resolve(environment: [String: String], bundle: [String: Any]) -> Backend? {
        func value(_ name: String) -> String? {
            for candidate in [environment[name], bundle[name] as? String] {
                let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let trimmed, !trimmed.isEmpty { return trimmed }
            }
            return nil
        }

        guard let raw = value("EXPO_PUBLIC_SUPABASE_URL"),
              let key = value("EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"),
              let url = URL(string: raw),
              // Requiring a known scheme and a host is what separates a
              // configured build from a silently broken one. `https://` parses
              // with a nil host, and a prefix test would accept `httpx`, so
              // both checks are exact rather than approximate.
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host()?.isEmpty == false
        else { return nil }

        return Backend(url: url, publishableKey: key)
    }
}

enum ConfigurationError: Error { case missing }
