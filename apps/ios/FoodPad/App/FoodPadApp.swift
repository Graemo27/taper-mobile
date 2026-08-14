import SwiftUI

@main
struct FoodPadApp: App {
    var body: some Scene {
        WindowGroup {
            JournalShellView(model: JournalComposition.makeModel())
                .preferredColorScheme(.light)
        }
    }
}

@MainActor
private enum JournalComposition {
    static func makeModel() -> JournalModel {
        let calendar = Calendar.current
        let today = JournalRepository.localDate(.now, calendar: calendar)
        let arguments = ProcessInfo.processInfo.arguments
        if let marker = arguments.firstIndex(of: "-FPJournalFixture"), arguments.indices.contains(marker + 1) {
            return fixture(arguments[marker + 1], today: today, calendar: calendar)
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

    private static func fixture(_ name: String, today: String, calendar: Calendar) -> JournalModel {
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: Date.now)!
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
