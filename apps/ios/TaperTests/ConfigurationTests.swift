import XCTest
@testable import Taper

/// The app read its backend settings from the process environment, which only
/// XCUITest ever populated. These cover the resolution rules that replaced it.
final class ConfigurationTests: XCTestCase {
    private let url = "https://example.supabase.co"
    private let key = "publishable-key"

    func testABuildWithNoEnvironmentIsStillConfigured() {
        let backend = AppConfiguration.resolve(
            environment: [:],
            bundle: [
                "EXPO_PUBLIC_SUPABASE_URL": url,
                "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": key,
            ]
        )
        XCTAssertEqual(backend?.url.absoluteString, url)
        XCTAssertEqual(backend?.publishableKey, key)
    }

    func testTheEnvironmentOutranksTheBuildSoATestCanRedirectIt() {
        let backend = AppConfiguration.resolve(
            environment: [
                "EXPO_PUBLIC_SUPABASE_URL": "https://other.supabase.co",
                "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": "other-key",
            ],
            bundle: [
                "EXPO_PUBLIC_SUPABASE_URL": url,
                "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": key,
            ]
        )
        XCTAssertEqual(backend?.url.absoluteString, "https://other.supabase.co")
        XCTAssertEqual(backend?.publishableKey, "other-key")
    }

    /// A missing or partial xcconfig leaves placeholders in Info.plist rather
    /// than failing the build, and the shapes that produces do not all fail the
    /// same way. Measured, not assumed:
    ///
    /// - `$(A)://$(B)`  — `URL(string:)` rejects outright: parens cannot appear
    ///                    in a host. The resolver never sees it.
    /// - `https://`     — **parses**, scheme `https`, host `nil`. This is what a
    ///                    defined scheme and an undefined host produce, and only
    ///                    the host check rejects it.
    /// - `://`          — parses with an *empty* scheme and no host.
    /// - `host.only`    — parses with no scheme at all.
    ///
    /// Every one of these would otherwise become a `Backend` that cannot reach
    /// anything, failing on each call as though the network were down.
    func testEveryUnsubstitutedShapeIsRejected() {
        let rejected = [
            "$(SUPABASE_URL_SCHEME)://$(SUPABASE_URL_HOST)",
            "https://",
            "://",
            "https:",
            "example.supabase.co",
            // A prefix test would accept this. Nothing generates it, but the
            // whole point of this guard is to be the thing that notices when
            // the build settings arrive wrong.
            "httpx://example.supabase.co",
        ]
        for raw in rejected {
            XCTAssertNil(
                AppConfiguration.resolve(
                    environment: [:],
                    bundle: [
                        "EXPO_PUBLIC_SUPABASE_URL": raw,
                        "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": key,
                    ]
                ),
                "\(raw) resolved to a backend"
            )
        }
    }

    func testBlankAndWhitespaceValuesAreTreatedAsAbsent() {
        XCTAssertNil(AppConfiguration.resolve(
            environment: ["EXPO_PUBLIC_SUPABASE_URL": url, "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": "   "],
            bundle: [:]
        ))
        XCTAssertNil(AppConfiguration.resolve(
            environment: [:],
            bundle: ["EXPO_PUBLIC_SUPABASE_URL": "", "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": key]
        ))
    }

    /// A half-populated environment must not shadow a complete build. The
    /// resolver falls back per value, not per source.
    func testAPartialEnvironmentFallsBackToTheBuildForWhatIsMissing() {
        let backend = AppConfiguration.resolve(
            environment: ["EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": "other-key"],
            bundle: [
                "EXPO_PUBLIC_SUPABASE_URL": url,
                "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": key,
            ]
        )
        XCTAssertEqual(backend?.url.absoluteString, url)
        XCTAssertEqual(backend?.publishableKey, "other-key")
    }
}
