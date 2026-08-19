import SwiftUI

/// Entry point.
///
/// Launches straight into onboarding. The launch diagnostic that stood here
/// while there were no screens has served its purpose — the backend and the
/// anonymous session were proven end to end, and it returns as a real screen
/// when there is something to persist.
@main
struct TaperApp: App {
    var body: some Scene {
        WindowGroup {
            OnboardingFlow()
                .preferredColorScheme(.light)
        }
    }
}
