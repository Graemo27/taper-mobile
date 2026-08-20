import SwiftUI

/// Entry point.
@main
struct TaperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
    }
}

/// What the app shows: the age gate, then whichever of four states the plan is
/// in.
///
/// Both things a launch needs to know now survive it. The gate's answer is kept
/// on the device, because it is a question with a permanent answer; the plan is
/// on the server, and is looked for before anything else is drawn.
///
/// The branch that matters is the one that does *not* fall through to
/// onboarding. `unknown` means the check failed, which is not the same as
/// having no plan — running the questions on that guess would take twelve
/// answers from a returning user and then overwrite the plan they were never
/// shown.
struct RootView: View {
    private let verification: any AdultVerificationStore

    @State private var isAdult: Bool
    @State private var isUnderage = false
    @State private var record: PlanRecord

    init(
        verification: any AdultVerificationStore = DeviceAdultVerification(),
        store: (any TaperPlanStoring)? = RootView.liveStore()
    ) {
        self.verification = verification
        _isAdult = State(initialValue: verification.isVerifiedAdult)
        _record = State(initialValue: PlanRecord(store: store))
    }

    /// The real store, or nil when this build has no backend.
    ///
    /// Nil rather than a crash, and nil rather than a store that fails at the
    /// first request: the app has already shipped once configured only while a
    /// test drove it, and the lesson was that an unconfigured build and an
    /// unreachable one looked identical. `PlanRecord` says which.
    static func liveStore() -> (any TaperPlanStoring)? {
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
        } else {
            switch record.status {
            case .checking:
                // Deliberately a rendered state rather than a blank frame. The
                // check is usually instant, and on a bad connection it is not —
                // a screen that shows nothing while it waits is one people tap
                // at.
                LookingForYourPlanView()
                    .task { await record.load() }
            case let .unknown(message):
                // Not onboarding. Whether a plan exists is unknown, and asking
                // twelve questions on a guess would overwrite the plan we could
                // not read.
                CannotCheckView(message: message) { Task { await record.load() } }
            case let .present(plan):
                // A row found and not readable is not a plan that can be
                // drawn. It reuses the could-not-check screen rather than
                // rendering a home screen with holes in it.
                if let progress = PlanProgress(plan: plan, today: Date()) {
                    HomeView(progress: progress)
                } else {
                    CannotCheckView(
                        message: "Your plan came back in a form this version can't read."
                    ) { Task { await record.load() } }
                }
            case .absent, .saving, .saveFailed:
                OnboardingFlow(
                    onFinish: { draft in Task { await record.submit(draft) } },
                    status: record.status
                )
            }
        }
    }
}

/// The moment before the app knows whether this person has a plan.
///
/// Usually invisible. It exists because the alternative — an empty frame, or
/// onboarding shown optimistically and yanked away — are both worse on the slow
/// connection where this state actually lasts.
struct LookingForYourPlanView: View {
    var body: some View {
        VStack(spacing: AppSpacing.l) {
            ProgressView().tint(AppColor.ink)
            Text("Looking for your plan…")
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.ground)
    }
}

/// Shown when the app could not find out whether a plan exists.
///
/// The distinction this screen protects is the whole reason `PlanStatus` has an
/// `unknown` case. Falling through to onboarding would ask a returning user to
/// answer twelve questions again and then write over the plan they were never
/// shown — so an unanswered question is reported rather than guessed at.
struct CannotCheckView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            Spacer(minLength: 0)

            Text("Can't reach your plan.")
                .font(AppFont.display(AppSize.title))
                .lineSpacing(AppLeading.title - AppSize.title)
                .foregroundStyle(AppColor.ink)

            Text(message)
                .font(AppFont.text(AppSize.body))
                .lineSpacing(AppLeading.relaxed - AppSize.body)
                .foregroundStyle(AppColor.inkMuted)

            Text("""
            Nothing has been lost. If you already have a plan it's still there — this is only \
            about reaching it.
            """)
                .font(AppFont.text(AppSize.caption))
                .lineSpacing(AppLeading.snug - AppSize.caption)
                .foregroundStyle(AppColor.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            OnboardingCTA(title: "Try again", action: onRetry, bottomPadding: 0)
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.bottom, AppSpacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppColor.ground)
    }
}
