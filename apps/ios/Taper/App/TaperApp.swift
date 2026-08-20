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
    @State private var submission: PlanSubmission

    init(
        verification: any AdultVerificationStore = DeviceAdultVerification(),
        store: (any TaperPlanWriting)? = RootView.liveStore()
    ) {
        self.verification = verification
        _isAdult = State(initialValue: verification.isVerifiedAdult)
        _submission = State(initialValue: PlanSubmission(store: store))
    }

    /// The real store, or nil when this build has no backend.
    ///
    /// Nil rather than a crash, and nil rather than a store that fails at the
    /// first request: the app has already shipped once configured only while a
    /// test drove it, and the lesson was that an unconfigured build and an
    /// unreachable one looked identical. `PlanSubmission` says which.
    static func liveStore() -> (any TaperPlanWriting)? {
        guard let backend = AppConfiguration.backend else { return nil }
        let client = AppSupabase.make(url: backend.url, publishableKey: backend.publishableKey)
        return SupabaseTaperPlanStore(
            client: client,
            session: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client))
        )
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
        } else if submission.state == .saved {
            OnboardingDoneView()
        } else {
            OnboardingFlow(
                onFinish: { draft in Task { await submission.submit(draft) } },
                saveState: submission.state
            )
        }
    }
}

/// Where the run stops, until there is a home screen to hand it to.
///
/// Says so plainly, for the same reason `OnboardingPlaceholderView` does: the
/// alternative is a "Start tracking" button that appears to work and lands
/// nowhere, which reads as a bug rather than as unfinished work.
///
/// It used to say nothing had been saved, which was true when it was written
/// and stopped being true the moment this screen moved behind a successful
/// write. Only reachable now when the plan is on the server.
struct OnboardingDoneView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("That's the plan.")
                .font(AppFont.display(AppSize.display))
                .foregroundStyle(AppColor.ink)

            Text("""
            Your plan is saved. Tracking is the next thing to build, so there's nowhere to log \
            against it yet — but the cap and the date are on the server, not just on this phone.
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
