import Foundation

struct JournalDay: Equatable, Identifiable {
    let date: String
    var entries: [JournalEntry]
    var id: String { date }
}

enum JournalPresentation {
    static func days(from entries: [JournalEntry]) -> [JournalDay] {
        var days: [JournalDay] = []
        var indices: [String: Int] = [:]
        for entry in entries {
            if let index = indices[entry.eatenOn] {
                days[index].entries.append(entry)
            } else {
                indices[entry.eatenOn] = days.count
                days.append(JournalDay(date: entry.eatenOn, entries: [entry]))
            }
        }
        return days
    }

    static func heading(for date: String, today: String, locale: Locale = .current) -> String {
        if date == today { return "Today" }
        if date == dayBefore(today) { return "Yesterday" }
        guard let value = dateValue(date) else { return date }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(
            date.prefix(4) == today.prefix(4) ? "EEEEMMMMd" : "yEEEEMMMMd"
        )
        return formatter.string(from: value)
    }

    static func thingCount(_ count: Int) -> String {
        count == 1 ? "1 thing" : "\(count) things"
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func dateValue(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func dayBefore(_ value: String) -> String {
        guard let date = dateValue(value),
              let previous = calendar.date(byAdding: .day, value: -1, to: date) else { return "" }
        return JournalRepository.localDate(previous, calendar: calendar)
    }
}

protocol MidnightClock: Sendable {
    func nextMidnight(after date: Date, calendar: Calendar) async throws -> Date
}

struct SystemMidnightClock: MidnightClock {
    func nextMidnight(after date: Date, calendar: Calendar) async throws -> Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
            .addingTimeInterval(1)
        try await Task.sleep(for: .seconds(max(0, midnight.timeIntervalSinceNow)))
        return .now
    }
}

@MainActor
final class JournalModel: ObservableObject {
    enum Status: Equatable { case loading, ready, failed }

    @Published private(set) var status: Status = .loading
    @Published private(set) var entries: [JournalEntry]
    @Published private(set) var today: String
    @Published private(set) var failedRemoval: String?
    @Published private(set) var confirmedRemovalIDs: Set<Int> = []
    let loadsAutomatically: Bool
    private let loadEntries: @Sendable () async throws -> [JournalEntry]
    private let deleteEntry: @Sendable (Int) async throws -> Bool
    private var reading = false
    private var removedIDs: Set<Int> = []

    init(
        entries: [JournalEntry] = [], today: String, loadsAutomatically: Bool = true,
        loadEntries: @escaping @Sendable () async throws -> [JournalEntry],
        deleteEntry: @escaping @Sendable (Int) async throws -> Bool = { _ in false }
    ) {
        self.entries = entries
        self.today = today
        self.loadsAutomatically = loadsAutomatically
        self.loadEntries = loadEntries
        self.deleteEntry = deleteEntry
    }

    func load() async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        status = .loading
        do {
            entries = try await loadEntries().filter { !removedIDs.contains($0.id) }
            status = .ready
        } catch {
            status = .failed
        }
    }

    func remove(_ entry: JournalEntry) async {
        failedRemoval = nil
        removedIDs.insert(entry.id)
        entries.removeAll { $0.id == entry.id }
        do {
            if try await deleteEntry(entry.id) { confirmedRemovalIDs.insert(entry.id) }
        } catch {
            removedIDs.remove(entry.id)
            failedRemoval = entry.name
            await load()
        }
    }

    func followMidnights(clock: any MidnightClock, calendar: Calendar, startingAt: Date = .now) async {
        var date = startingAt
        today = JournalRepository.localDate(date, calendar: calendar)
        while !Task.isCancelled {
            do { date = try await clock.nextMidnight(after: date, calendar: calendar) }
            catch { return }
            today = JournalRepository.localDate(date, calendar: calendar)
        }
    }
}
