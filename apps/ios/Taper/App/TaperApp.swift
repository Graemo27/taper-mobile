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

/// What the app shows: onboarding, and the wall it currently ends at.
///
/// The state is deliberately not persisted. Onboarding has nowhere to write to
/// yet, so a relaunch starts the run over — which is the truth, and better than
/// a flag that remembers a plan the app never saved.
struct RootView: View {
    @State private var hasFinishedOnboarding = false

    var body: some View {
        if hasFinishedOnboarding {
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
