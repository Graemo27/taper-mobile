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

struct JournalDraft: Equatable, Sendable {
    let fdcID: Int
    let name: String
    let servingLabel: String
    let servings: Int
    let grams: Double
    let kcal: Int?
    let proteinG: Double?
    let fibreG: Double?
}

protocol JournalWriteDataSource: Sendable {
    func save(userID: UUID, eatenOn: String, draft: JournalDraft) async throws -> JournalEntry
}

protocol JournalDeleteDataSource: Sendable {
    func remove(userID: UUID, id: Int) async throws
}

struct SupabaseJournalDeleteDataSource: JournalDeleteDataSource {
    let client: SupabaseClient

    func remove(userID: UUID, id: Int) async throws {
        try await client.from("journal_entries").delete()
            .eq("id", value: id).eq("user_id", value: userID.uuidString).execute()
    }
}

struct SupabaseJournalWriteDataSource: JournalWriteDataSource {
    let client: SupabaseClient

    func save(userID: UUID, eatenOn: String, draft: JournalDraft) async throws -> JournalEntry {
        try await client.from("journal_entries").insert(Row(
            userID: userID, eatenOn: eatenOn, fdcID: draft.fdcID, name: draft.name,
            servingLabel: draft.servingLabel, servings: draft.servings, grams: draft.grams,
            kcal: draft.kcal, proteinG: draft.proteinG, fibreG: draft.fibreG
        )).select("id,eaten_on,name,serving_label,kcal").single().execute().value
    }

    private struct Row: Encodable {
        let userID: UUID
        let eatenOn: String
        let fdcID: Int
        let name: String
        let servingLabel: String
        let servings: Int
        let grams: Double
        let kcal: Int?
        let proteinG: Double?
        let fibreG: Double?

        enum CodingKeys: String, CodingKey {
            case name, servings, grams, kcal
            case userID = "user_id"
            case eatenOn = "eaten_on"
            case fdcID = "fdc_id"
            case servingLabel = "serving_label"
            case proteinG = "protein_g"
            case fibreG = "fibre_g"
        }
    }
}

struct JournalWriteRepository: Sendable {
    let sessions: SessionCoordinator
    let source: any JournalWriteDataSource

    func save(
        _ draft: JournalDraft, at date: Date = .now, calendar: Calendar = .current
    ) async throws -> JournalEntry {
        let eatenOn = JournalRepository.localDate(date, calendar: calendar)
        return try await sessions.authenticated { userID in
            try await source.save(userID: userID, eatenOn: eatenOn, draft: draft)
        }
    }
}

struct JournalDeleteRepository: Sendable {
    let sessions: SessionCoordinator
    let source: any JournalDeleteDataSource

    func remove(id: Int) async throws {
        try await sessions.authenticated { try await source.remove(userID: $0, id: id) }
    }
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
