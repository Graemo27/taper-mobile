import Foundation

@MainActor
/// Recent foods for the empty search screen. A failed read keeps the previous
/// list and says nothing — Recent is an offer, not an answer.
final class RecentFoodsModel: ObservableObject {
    @Published private(set) var foods: [RecentFood]
    private let read: @Sendable () async throws -> [RecentFood]
    private var reading = false

    init(foods: [RecentFood] = [], read: @escaping @Sendable () async throws -> [RecentFood]) {
        self.foods = foods
        self.read = read
    }

    func load() async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        do { foods = try await read() } catch {}
    }
}
