import SwiftUI

@main
struct FoodPadApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let fixture = AppComposition.searchFixture {
                    SearchFlowView(model: SearchComposition.fixture(fixture), initialQuery: "ap")
                } else {
                    AppRootView(
                        journal: JournalComposition.makeModel(),
                        search: SearchComposition.makeModel()
                    )
                }
            }
            .preferredColorScheme(.light)
        }
    }
}

private struct AppRootView: View {
    let journal: JournalModel
    let search: SearchModel
    @State private var isSearching = false

    var body: some View {
        JournalShellView(model: journal) { isSearching = true }
            .navigationDestination(isPresented: $isSearching) { SearchFlowView(model: search) }
    }
}

private enum AppComposition {
    static var searchFixture: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: "-FPSearchFixture"),
              arguments.indices.contains(marker + 1) else { return nil }
        return arguments[marker + 1]
    }
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
        let repository = JournalRepository(
            sessions: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client)),
            source: SupabaseJournalDataSource(client: client)
        )
        return JournalModel(today: today) { try await repository.listEntries() }
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
