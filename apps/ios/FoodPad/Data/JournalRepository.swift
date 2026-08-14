import Foundation
import Supabase

struct JournalEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: Int
    let eatenOn: String
    let name: String
    let servingLabel: String?
    let kcal: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, kcal
        case eatenOn = "eaten_on"
        case servingLabel = "serving_label"
    }
}

struct JournalPage: Sendable {
    let entries: [JournalEntry]
    let total: Int?
}

protocol JournalDataSource: Sendable {
    func fetch(userID: UUID, from start: String, limit: Int) async throws -> JournalPage
}

struct SupabaseJournalDataSource: JournalDataSource {
    let client: SupabaseClient

    func fetch(userID: UUID, from start: String, limit: Int) async throws -> JournalPage {
        let response: PostgrestResponse<[JournalEntry]> = try await client
            .from("journal_entries")
            .select("id,eaten_on,name,serving_label,kcal", count: .exact)
            .eq("user_id", value: userID.uuidString)
            .gte("eaten_on", value: start)
            .order("eaten_on", ascending: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        return JournalPage(entries: response.value, total: response.count)
    }
}

struct JournalRepository: Sendable {
    static let readCap = 2_000
    let sessions: SessionCoordinator
    let source: any JournalDataSource

    func listEntries(today: Date = .now, calendar: Calendar = .current) async throws -> [JournalEntry] {
        let start = Self.windowStart(today: today, calendar: calendar)
        return try await sessions.authenticated { userID in
            let page = try await source.fetch(userID: userID, from: start, limit: Self.readCap)
            return Self.dropPartialOldestDay(from: page)
        }
    }

    static func dropPartialOldestDay(from page: JournalPage) -> [JournalEntry] {
        let rows = page.entries
        guard let total = page.total, total > rows.count, let oldest = rows.last?.eatenOn,
              rows.contains(where: { $0.eatenOn != oldest }) else { return rows }
        return rows.filter { $0.eatenOn != oldest }
    }

    static func windowStart(today: Date, calendar: Calendar) -> String {
        let calendar = gregorianCalendar(in: calendar.timeZone)
        return localDate(calendar.date(byAdding: .day, value: -29, to: today)!, calendar: calendar)
    }

    static func localDate(_ date: Date, calendar: Calendar) -> String {
        let calendar = gregorianCalendar(in: calendar.timeZone)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
