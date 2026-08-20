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
            RootView()
                .preferredColorScheme(.light)
        }
    }
}

/// What the app shows: the age gate, then onboarding, then the wall it
/// currently ends at.
///
/// Only the gate's answer survives a relaunch, and only because it is a
/// question with a permanent answer. The onboarding state is deliberately not
/// persisted — there is nowhere to write it yet, so a relaunch starts the run
/// over, which is the truth and better than a flag remembering a plan the app
/// never saved.
struct RootView: View {
    private let verification: any AdultVerificationStore

    @State private var isAdult: Bool
    @State private var isUnderage = false
    @State private var hasFinishedOnboarding = false

    init(verification: any AdultVerificationStore = DeviceAdultVerification()) {
        self.verification = verification
        _isAdult = State(initialValue: verification.isVerifiedAdult)
    }

    var body: some View {
        if isUnderage {
            UnderageView { isUnderage = false }
        } else if !isAdult {
            AgeGateView(
                onVerified: {
                    // Recorded before the screen changes, so the answer
                    // survives a relaunch rather than only this run.
                    verification.recordAdult()
                    isAdult = true
                },
                onUnderage: { isUnderage = true }
            )
        } else if hasFinishedOnboarding {
            OnboardingDoneView()
        } else {
            OnboardingFlow { hasFinishedOnboarding = true }
        }
    }
}

/// Where the run stops, until there is a home screen to hand it to.
///
/// Says so plainly, for the same reason `OnboardingPlaceholderView` does: the
/// alternative is a "Start tracking" button that appears to work and lands
/// nowhere, which reads as a bug rather than as unfinished work. It also says
/// that nothing was saved, because nothing was.
struct OnboardingDoneView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("That's the plan.")
                .font(AppFont.display(AppSize.display))
                .foregroundStyle(AppColor.ink)

            Text("""
            Tracking is the next thing to build. Your answers are held for this run only — \
            nothing has been saved yet, so relaunching starts you over.
            """)
                .font(AppFont.text(AppSize.body))
                .lineSpacing(AppLeading.relaxed - AppSize.body)
                .foregroundStyle(AppColor.inkMuted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AppLayout.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppColor.ground)
    }
}
