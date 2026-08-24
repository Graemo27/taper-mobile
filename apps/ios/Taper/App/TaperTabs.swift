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
    /// Whether home has pushed the day's list on top of itself.
    ///
    /// A flag rather than a `NavigationStack` path, because there is one
    /// destination and the bar has to stay put underneath it. A stack here
    /// would bring its own bar to hide and would take the tab bar with it on
    /// push, which is the one thing the board is explicit about: L7 keeps the
    /// bar, with home still lit.
    @State private var isShowingToday = false
    /// The check-in being looked at, one level above the list.
    @State private var editing: StoredCheckIn?
    @State private var pastDays: PastDaysRecord
    /// The catalogue search, kept for the session so a half-typed brand name
    /// survives a glance at the plan tab.
    @State private var search: TreatmentSearchRecord
    @State private var isSearching = false
    /// The key being made, if the search led to one.
    @State private var draft: NewKeyDraft?
    @State private var pad: PadRecord
    @State private var today: TodayRecord

    init(progress: PlanProgress, stores: AppStores?) {
        self.progress = progress
        self.stores = stores
        _pad = State(initialValue: PadRecord(store: stores?.pad))
        _today = State(initialValue: TodayRecord(store: stores?.checkIns))
        _search = State(initialValue: TreatmentSearchRecord(search: stores?.nrt))
        _pastDays = State(initialValue: PastDaysRecord(
            checkIns: stores?.checkIns, plans: stores?.planVersions
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch selection {
            case .home:
                if let editing {
                    CheckInEditView(
                        entry: editing,
                        failure: today.removeFailure,
                        isRemoving: today.isRemoving,
                        onRemove: {
                            Task {
                                await today.remove(editing)
                                // Only leave if it landed. A failed delete has
                                // a sentence to show, and showing it on the
                                // screen somebody has already left is the same
                                // as not showing it.
                                if today.removeFailure == nil { self.editing = nil }
                            }
                        },
                        onBack: { self.editing = nil }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if isShowingToday {
                    TodayListView(
                        status: today.status,
                        entries: today.entries,
                        summary: today.summary(ceilingMg: progress.todaysCapMg),
                        onBack: { isShowingToday = false },
                        onSelect: { editing = $0 },
                        pastDays: pastDays.rollups,
                        arePastDaysUnavailable: pastDays.isUnavailable,
                        today: Date(),
                        hasEarlier: pastDays.hasEarlier,
                        onShowEarlier: { Task { await pastDays.showEarlier() } },
                        isLoadingEarlier: pastDays.isLoadingEarlier
                    )
                    .task { await pastDays.load() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    HomeView(
                        progress: progress,
                        today: today,
                        onCheckIn: { selection = .log },
                        onSeeHistory: { isShowingToday = true }
                    )
                }
            case .log:
                PadView(
                    status: pad.status,
                    record: today,
                    ceilingMg: progress.todaysCapMg,
                    search: search,
                    isSearching: $isSearching,
                    draft: $draft,
                    draftFor: { NewKeyDraft(product: $0, store: stores?.pad) },
                    onKeyAdded: { Task { await pad.load() } }
                )
            case .plan:
                PlanTabView(progress: progress)
            }

            TaperTabBar(selection: $selection)
        }
        .animation(.easeOut(duration: 0.22), value: isShowingToday)
        .background(AppColor.ground)
        // Home needs the day for its tracking card; the pad needs the keys as
        // well. Neither read holds a screen up — both tabs draw their plan
        // figures first and fill the day in — and `PadRecord` and `TodayRecord`
        // each guard against a second read, so returning to a tab is free.
        //
        // Keyed on the tab so switching re-reads. That is what refreshes home
        // after a check-in made on the pad, and it is also the path that put
        // `TodayRecord` under a reload-during-removal race worth remembering.
        .task(id: selection) {
            switch selection {
            case .home:
                await today.load()
            case .log:
                await pad.load()
                await today.load()
            case .plan:
                break
            }
        }
    }
}
