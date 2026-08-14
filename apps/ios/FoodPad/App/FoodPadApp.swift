import SwiftUI

@main
struct FoodPadApp: App {
    @StateObject private var favourites = FavouritesComposition.makeModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let fixture = AppComposition.foodFixture {
                    FoodDetailView(
                        model: FoodComposition.fixture(fixture),
                        saveModel: SaveComposition.fixture(AppComposition.saveFixture),
                        fdcID: 101
                    )
                } else if let fixture = AppComposition.searchFixture {
                    SearchFlowView(
                        model: SearchComposition.fixture(fixture),
                        recent: RecentComposition.makeModel(),
                        initialQuery: fixture == "idle" ? "" : "ap",
                        fetch: FoodComposition.fixtureFetcher()
                    )
                } else {
                    AppRootView(
                        journal: JournalComposition.makeModel(),
                        search: SearchComposition.makeModel(),
                        recent: RecentComposition.makeModel(),
                        fetch: SearchComposition.makeFetcher(),
                        save: SearchComposition.makeSaver()
                    )
                }
            }
            .environmentObject(favourites)
            .preferredColorScheme(.light)
        }
    }
}

private struct AppRootView: View {
    let journal: JournalModel
    let search: SearchModel
    let recent: RecentFoodsModel
    let fetch: @Sendable (Int) async throws -> Food
    let save: @Sendable (JournalDraft) async throws -> Void
    @State private var isSearching = false

    var body: some View {
        JournalShellView(model: journal) { isSearching = true }
            .navigationDestination(isPresented: $isSearching) {
                SearchFlowView(model: search, recent: recent, fetch: fetch, save: save)
            }
            .onChange(of: isSearching) { _, visible in
                if !visible { Task { await journal.load() } }
            }
    }
}

private enum AppComposition {
    static var foodFixture: String? { fixture(after: "-FPFoodFixture") }
    static var favouriteFixture: String? { fixture(after: "-FPFavouriteFixture") }
    static var recentFixture: String? { fixture(after: "-FPRecentFixture") }
    static var saveFixture: String? { fixture(after: "-FPSaveFixture") }
    static var searchFixture: String? { fixture(after: "-FPSearchFixture") }
    static var journalE2E: Bool { ProcessInfo.processInfo.arguments.contains("-FPJournalE2E") }
    static var journalE2ECleanup: Bool { ProcessInfo.processInfo.arguments.contains("-FPJournalE2ECleanup") }

    private static func fixture(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: flag),
              arguments.indices.contains(marker + 1) else { return nil }
        return arguments[marker + 1]
    }
}

@MainActor
private enum RecentComposition {
    static func makeModel() -> RecentFoodsModel {
        if AppComposition.recentFixture == "refreshes" {
            let fixture = RefreshFixture()
            return RecentFoodsModel { await fixture.read() }
        }
        let environment = ProcessInfo.processInfo.environment
        guard let url = URL(string: environment["EXPO_PUBLIC_SUPABASE_URL"] ?? ""),
              let key = environment["EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
            return RecentFoodsModel { throw ConfigurationError.missing }
        }
        let client = AppSupabase.make(url: url, publishableKey: key)
        let repository = RecentFoodsRepository(
            sessions: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client)),
            source: SupabaseRecentFoodsDataSource(client: client)
        )
        return RecentFoodsModel { try await repository.list() }
    }

    private actor RefreshFixture {
        private var reads = 0
        func read() -> [RecentFood] {
            reads += 1
            return [RecentFood(
                fdcID: 101, name: "Apple", servingLabel: reads == 1 ? "1 medium" : "2 medium", kcal: 95
            )]
        }
    }

    private enum ConfigurationError: Error { case missing }
}

@MainActor
private enum FavouritesComposition {
    static func makeModel() -> FavouritesModel {
        if let fixture = AppComposition.favouriteFixture {
            let initial: Set<Int> = fixture == "on" ? [101] : []
            return FavouritesModel(read: { initial }) { _, _ in
                if fixture == "fails" { throw FixtureError.failed }
            }
        }
        let environment = ProcessInfo.processInfo.environment
        guard let url = URL(string: environment["EXPO_PUBLIC_SUPABASE_URL"] ?? ""),
              let key = environment["EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
            return FavouritesModel(read: { throw FixtureError.failed }, persist: { _, _ in throw FixtureError.failed })
        }
        let client = AppSupabase.make(url: url, publishableKey: key)
        let repository = FavouritesRepository(
            sessions: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client)),
            source: SupabaseFavouritesDataSource(client: client)
        )
        return FavouritesModel(read: { try await repository.list() }, persist: repository.set)
    }

    private enum FixtureError: Error { case failed }
}

@MainActor
private enum SearchComposition {
    static func makeModel() -> SearchModel {
        let environment = ProcessInfo.processInfo.environment
        guard let url = URL(string: environment["EXPO_PUBLIC_SUPABASE_URL"] ?? ""),
              let key = environment["EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
            return SearchModel { _ in throw ConfigurationError.missing }
        }
        let client = AppSupabase.make(url: url, publishableKey: key)
        let repository = FoodSearchRepository(
            sessions: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client)),
            source: SupabaseFoodSearchDataSource(client: client)
        )
        return SearchModel { try await repository.search($0) }
    }

    static func makeFetcher() -> @Sendable (Int) async throws -> Food {
        let environment = ProcessInfo.processInfo.environment
        guard let url = URL(string: environment["EXPO_PUBLIC_SUPABASE_URL"] ?? ""),
              let key = environment["EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
            return { _ in throw ConfigurationError.missing }
        }
        let client = AppSupabase.make(url: url, publishableKey: key)
        let repository = FoodSearchRepository(
            sessions: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client)),
            source: SupabaseFoodSearchDataSource(client: client)
        )
        return { try await repository.food(fdcID: $0) }
    }

    static func makeSaver() -> @Sendable (JournalDraft) async throws -> Void {
        let environment = ProcessInfo.processInfo.environment
        guard let url = URL(string: environment["EXPO_PUBLIC_SUPABASE_URL"] ?? ""),
              let key = environment["EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
            return { _ in throw ConfigurationError.missing }
        }
        let client = AppSupabase.make(url: url, publishableKey: key)
        let repository = JournalWriteRepository(
            sessions: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client)),
            source: SupabaseJournalWriteDataSource(client: client)
        )
        return { _ = try await repository.save($0) }
    }

    static func fixture(_ name: String) -> SearchModel {
        let results = foods
        switch name {
        case "results": return SearchModel { _ in FoodSearchResult(foods: results, unavailable: 0) }
        case "empty": return SearchModel { _ in FoodSearchResult(foods: [], unavailable: 0) }
        case "failed": return SearchModel { _ in throw FixtureError.failed }
        default:
            return SearchModel { _ in
                try await Task.sleep(for: .seconds(60))
                return FoodSearchResult(foods: [], unavailable: 0)
            }
        }
    }

    private static let foods = [
        Food(
            fdcId: 101, name: "Apple", category: "Fruit", dataType: "Foundation",
            portion: Portion(label: "1 medium", grams: 182),
            per100g: Nutrients(kcal: 52, proteinG: 0.3, fibreG: 2.4, vitaminEMg: 0.2, magnesiumMg: 5, unsaturatedFatG: 0.1),
            perServing: Nutrients(kcal: 95, proteinG: 0.5, fibreG: 4.4, vitaminEMg: 0.3, magnesiumMg: 9, unsaturatedFatG: 0.2),
            portions: [Portion(label: "1 medium", grams: 182)]
        ),
        Food(
            fdcId: 102, name: "Apple juice", category: "Beverages", dataType: "Foundation",
            portion: nil, per100g: .empty, perServing: nil, portions: []
        ),
    ]

    private enum ConfigurationError: Error { case missing }
    private enum FixtureError: Error { case failed }
}

@MainActor
private enum FoodComposition {
    static func fixtureFetcher() -> @Sendable (Int) async throws -> Food {
        let food = fixtureFood
        return { _ in food }
    }

    static func fixture(_ name: String) -> FoodLookupModel {
        let food = fixtureFood
        switch name {
        case "loaded": return FoodLookupModel { _ in food }
        case "missing": return FoodLookupModel { _ in
            throw FoodSearchError("That food could not be found.", kind: .http, status: 404)
        }
        case "failed": return FoodLookupModel { _ in throw FixtureError.failed }
        default: return FoodLookupModel { _ in
            try await Task.sleep(for: .seconds(60))
            return food
        }
        }
    }

    private static let fixtureFood = Food(
        fdcId: 101, name: "Almonds", category: "Nuts", dataType: "Foundation",
        portion: Portion(label: "1 oz", grams: 28),
        per100g: Nutrients(kcal: 579, proteinG: 21.2, fibreG: 12.5, vitaminEMg: 25.6, magnesiumMg: 270, unsaturatedFatG: 43.9),
        perServing: nil, portions: [Portion(label: "1 oz", grams: 28)]
    )

    private enum FixtureError: Error { case failed }
}

@MainActor
private enum SaveComposition {
    static func fixture(_ name: String?) -> FoodSaveModel {
        name == "succeeds"
            ? FoodSaveModel(save: { _ in })
            : FoodSaveModel(save: { _ in throw FixtureError.failed })
    }

    private enum FixtureError: Error { case failed }
}

@MainActor
private enum JournalComposition {
    static func makeModel() -> JournalModel {
        let calendar = Calendar.current
        let launchedAt = Date.now
        let today = JournalRepository.localDate(launchedAt, calendar: calendar)
        let arguments = ProcessInfo.processInfo.arguments
        if let marker = arguments.firstIndex(of: "-FPJournalFixture"), arguments.indices.contains(marker + 1) {
            return fixture(arguments[marker + 1], today: today, launchedAt: launchedAt, calendar: calendar)
        }

        let environment = ProcessInfo.processInfo.environment
        guard let url = URL(string: environment["EXPO_PUBLIC_SUPABASE_URL"] ?? ""),
              let key = environment["EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
            return JournalModel(today: today) { throw ConfigurationError.missing }
        }
        let client = AppSupabase.make(url: url, publishableKey: key)
        let sessions = SessionCoordinator(auth: SupabaseAnonymousAuth(client: client))
        let repository = JournalRepository(
            sessions: sessions,
            source: SupabaseJournalDataSource(client: client)
        )
        let deletion = JournalDeleteRepository(
            sessions: sessions, source: SupabaseJournalDeleteDataSource(client: client)
        )
        if AppComposition.journalE2E || AppComposition.journalE2ECleanup {
            let harness = JournalE2EHarness(
                read: repository,
                write: JournalWriteRepository(
                    sessions: sessions, source: SupabaseJournalWriteDataSource(client: client)
                ),
                deletion: deletion
            )
            if AppComposition.journalE2ECleanup {
                return JournalModel(today: today) { try await harness.cleanup(); return [] }
            }
            return JournalModel(
                today: today, loadEntries: { try await harness.load() },
                deleteEntry: { try await harness.remove(id: $0) }
            )
        }
        return JournalModel(
            today: today, loadEntries: { try await repository.listEntries() },
            deleteEntry: { id in try await deletion.remove(id: id); return false }
        )
    }

    private static func fixture(_ name: String, today: String, launchedAt: Date, calendar: Calendar) -> JournalModel {
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: launchedAt)!
        let yesterday = JournalRepository.localDate(yesterdayDate, calendar: calendar)
        let rows = [
            JournalEntry(id: 101, eatenOn: today, name: "Apple", servingLabel: "1 medium", kcal: 95),
            JournalEntry(id: 102, eatenOn: today, name: "Toast", servingLabel: nil, kcal: nil),
            JournalEntry(id: 103, eatenOn: yesterday, name: "Soup", servingLabel: "1 bowl", kcal: 180),
        ]
        switch name {
        case "populated": return JournalModel(today: today) { rows }
        case "failed-with-rows": return JournalModel(entries: rows, today: today) { throw FixtureError.failed }
        case "failed": return JournalModel(today: today) { throw FixtureError.failed }
        case "loading": return JournalModel(today: today, loadsAutomatically: false) { [] }
        default: return JournalModel(today: today) { [] }
        }
    }

    private enum ConfigurationError: Error { case missing }
    private enum FixtureError: Error { case failed }
}

private actor JournalE2EHarness {
    private static let name = "FP swipe test"
    private static let pendingKey = "JournalE2EPendingRowIDs"
    let read: JournalRepository
    let write: JournalWriteRepository
    let deletion: JournalDeleteRepository
    private var seeded: JournalEntry?

    init(read: JournalRepository, write: JournalWriteRepository, deletion: JournalDeleteRepository) {
        self.read = read
        self.write = write
        self.deletion = deletion
    }

    func load() async throws -> [JournalEntry] {
        if let seeded { return [seeded] }
        try await cleanup()
        let entry = try await write.save(JournalDraft(
            fdcID: 1, name: Self.name, servingLabel: "1 test serving", servings: 1,
            grams: 1, kcal: 1, proteinG: nil, fibreG: nil
        ))
        record(entry.id)
        seeded = entry
        return [entry]
    }

    func remove(id: Int) async throws -> Bool {
        try await deletion.remove(id: id)
        return try await !read.listEntries().contains { $0.id == id }
    }

    func cleanup() async throws {
        for id in pendingIDs {
            try await deletion.remove(id: id)
            forget(id)
        }
        for entry in (try? await read.listEntries()) ?? [] where entry.name == Self.name {
            try await deletion.remove(id: entry.id)
        }
    }

    private var pendingIDs: [Int] {
        UserDefaults.standard.array(forKey: Self.pendingKey) as? [Int] ?? []
    }

    private func record(_ id: Int) {
        UserDefaults.standard.set(Array(Set(pendingIDs + [id])), forKey: Self.pendingKey)
        UserDefaults.standard.synchronize()
    }

    private func forget(_ id: Int) {
        UserDefaults.standard.set(pendingIDs.filter { $0 != id }, forKey: Self.pendingKey)
        UserDefaults.standard.synchronize()
    }
}
