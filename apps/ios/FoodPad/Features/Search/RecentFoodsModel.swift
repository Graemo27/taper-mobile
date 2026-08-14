import Foundation

@MainActor
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
