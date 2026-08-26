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
    /// L5, when a result's label is open.
    @State private var facts: ProductDetailRecord?
    /// The source key being typed, if the pad's other run was tapped.
    @State private var sourceDraft: NewSourceDraft?
    /// Editing the pad, kept for the session so the mode survives a tab away.
    @State private var edit: PadEditRecord
    @State private var pad: PadRecord
    @State private var today: TodayRecord
    /// The daily check-in's answer, kept for the session like the rest.
    @State private var rating: DayRatingRecord
    /// The graph's days, kept for the session like the rest.
    @State private var trend: TrendRecord
    /// The craving being got through, if one is open.
    ///
    /// Built on the way in and dropped on the way out rather than kept for the
    /// session like the records above it. Those hold work in progress; this one
    /// holds a write that has happened, and re-presenting a spent record would
    /// show a screen that had already counted somebody's last craving.
    @State private var craving: CravingRecord?

    init(progress: PlanProgress, stores: AppStores?) {
        self.progress = progress
        self.stores = stores
        _pad = State(initialValue: PadRecord(store: stores?.pad))
        _today = State(initialValue: TodayRecord(store: stores?.checkIns))
        _rating = State(initialValue: DayRatingRecord(store: stores?.ratings))
        _trend = State(initialValue: TrendRecord(
            checkIns: stores?.checkIns, plans: stores?.planVersions
        ))
        _search = State(initialValue: TreatmentSearchRecord(search: stores?.nrt))
        _edit = State(initialValue: PadEditRecord(store: stores?.pad))
        _pastDays = State(initialValue: PastDaysRecord(
            checkIns: stores?.checkIns, plans: stores?.planVersions
        ))
    }

    /// The pad, when there is one to read. Nil mid-load or after a failed
    /// read, which is not the same as an empty pad — the craving screen offers
    /// nothing rather than guessing at what is on it.
    private var padKeys: Pad? {
        if case let .ready(pad) = pad.status { return pad }
        return nil
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
                        pad: padKeys,
                        rating: rating,
                        trend: trend,
                        onCheckIn: { selection = .log },
                        onSeeHistory: { isShowingToday = true },
                        onCraving: { craving = CravingRecord(store: stores?.checkIns) }
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
                    facts: $facts,
                    factsFor: { ProductDetailRecord(product: $0, store: stores?.checkIns) },
                    onProductLogged: { today.fold($0) },
                    draftFor: { NewKeyDraft(product: $0, store: stores?.pad) },
                    sourceDraft: $sourceDraft,
                    newSourceDraft: { NewSourceDraft(store: stores?.pad) },
                    onKeyAdded: { stored in
                        // Reloaded only when there is no pad to add to — mid
                        // load, or after a read that failed.
                        if !pad.insert(stored) { Task { await pad.load() } }
                    },
                    edit: edit,
                    onKeyRemoved: { id in
                        // A failure is not proof the key survived. The delete
                        // may have committed and lost its answer, leaving the
                        // key gone on the server and drawn here — and the retry
                        // the message invites then fails too, because the row
                        // is already missing. So an unconfirmed removal asks
                        // the server rather than assuming either way.
                        if let id, pad.drop(id) { return }
                        Task { await pad.load() }
                    }
                )
            case .plan:
                PlanTabView(progress: progress)
            }

            TaperTabBar(selection: $selection)
        }
        // A cover rather than a push: L8 is the one screen the board draws
        // without the tab bar, and it is drawn that way because somebody
        // mid-craving is doing one thing. It closes itself the moment it has
        // written its row.
        .fullScreenCover(item: $craving) { record in
            CravingView(
                record: record,
                suggestion: CravingRecord.suggestion(from: padKeys),
                putAwayTitle: CravingRecord.putAwayTitle(for: padKeys),
                // Neither way out is open while the write is: the task
                // outlives the cover, so a screen dismissed mid-write lets a
                // second one be opened and a second row written for one
                // craving. `CravingView` dims both controls to say so.
                onClose: { if !record.isWriting { craving = nil } },
                onLogged: { written in
                    today.fold(written)
                    craving = nil
                },
                onLogSomethingElse: {
                    guard !record.isWriting else { return }
                    craving = nil
                    selection = .log
                }
            )
        }
        .animation(.easeOut(duration: 0.22), value: isShowingToday)
        .background(AppColor.ground)
        // Home needs the day for its tracking card, and the keys as well: the
        // craving button opens a screen that suggests one, and reading the pad
        // only on the log tab left that suggestion missing for anyone who had
        // not been there this session — which is how it shipped for exactly one
        // test run. Neither read holds a screen up, and both records guard
        // against a second read, so returning to a tab is free.
        //
        // Keyed on the tab so switching re-reads. That is what refreshes home
        // after a check-in made on the pad, and it is also the path that put
        // `TodayRecord` under a reload-during-removal race worth remembering.
        .task(id: selection) {
            switch selection {
            case .home:
                await today.load()
                await pad.load()
                await rating.load()
                await trend.load()
            case .log:
                await pad.load()
                await today.load()
            case .plan:
                break
            }
        }
    }
}
