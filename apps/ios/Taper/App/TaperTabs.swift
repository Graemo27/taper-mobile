import SwiftUI

/// What the app is once there is a plan: three tabs over one bar.
///
/// Hand-rolled rather than a `TabView`, because the bar is drawn from the
/// board — its own border, spacing and marks — and a system bar styled to look
/// like that one is a fight that has to be re-fought every OS release.
///
/// The pad's records are made here and kept for the whole session. Rebuilding
/// them per tab switch would drop a half-typed selection every time somebody
/// checked their plan mid-count.
struct TaperTabs: View {
    let progress: PlanProgress
    let stores: AppStores?

    @State private var selection: TaperTab = .home
    @State private var pad: PadRecord
    @State private var today: TodayRecord

    init(progress: PlanProgress, stores: AppStores?) {
        self.progress = progress
        self.stores = stores
        _pad = State(initialValue: PadRecord(store: stores?.pad))
        _today = State(initialValue: TodayRecord(store: stores?.checkIns))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch selection {
            case .home:
                HomeView(progress: progress)
            case .log:
                PadView(status: pad.status, record: today, ceilingMg: progress.todaysCapMg)
            case .plan:
                UnbuiltPlanView()
            }

            TaperTabBar(selection: $selection)
        }
        .background(AppColor.ground)
        // Both reads start when the pad is first opened rather than at launch:
        // somebody who only wants to see their cap should not wait on two
        // requests they never asked for. `PadRecord` and `TodayRecord` each
        // guard against a second read, so returning to the tab is free.
        .task(id: selection) {
            guard selection == .log else { return }
            await pad.load()
            await today.load()
        }
    }
}

/// L4, which does not exist yet.
///
/// A tab that leads somewhere honest rather than one that appears later. A bar
/// that grows a tab is one people have to re-learn, and the board draws three.
struct UnbuiltPlanView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Your plan")
                .font(AppFont.display(AppSize.title))
                .foregroundStyle(AppColor.ink)
            Text("""
            The whole taper — every week's cap and the date it reaches zero — belongs here. \
            It isn't built yet. Today's cap is on the home tab in the meantime.
            """)
                .font(AppFont.text(AppSize.caption))
                .lineSpacing(AppLeading.snug - AppSize.caption)
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppLayout.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, AppSpacing.giant)
        .background(AppColor.ground)
    }
}
