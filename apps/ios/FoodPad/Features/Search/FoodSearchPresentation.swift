import Foundation

@MainActor
final class SearchModel: ObservableObject {
    enum Status: Equatable { case idle, loading, ready, failed }

    @Published private(set) var status: Status = .idle
    @Published private(set) var foods: [Food] = []
    @Published private(set) var resolvedQuery = ""
    @Published private(set) var failure: FoodSearchError?
    private let performSearch: @Sendable (String) async throws -> FoodSearchResult
    private var generation = 0

    init(search: @escaping @Sendable (String) async throws -> FoodSearchResult) {
        performSearch = search
    }

    func search(_ rawQuery: String) async {
        generation += 1
        let request = generation
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            status = .idle
            foods = []
            failure = nil
            return
        }
        status = .loading
        do {
            let result = try await performSearch(query)
            guard generation == request else { return }
            foods = result.foods
            resolvedQuery = query
            failure = nil
            status = .ready
        } catch is CancellationError {
            return
        } catch {
            guard generation == request else { return }
            failure = error as? FoodSearchError
                ?? FoodSearchError("Food lookup is unavailable right now.", kind: .http)
            resolvedQuery = query
            status = .failed
        }
    }
}

@MainActor
final class FoodLookupModel: ObservableObject {
    enum Status: Equatable { case looking, held, missing, failed }

    @Published private(set) var status: Status = .looking
    @Published private(set) var food: Food?
    @Published private(set) var failure: FoodSearchError?
    private let fetch: @Sendable (Int) async throws -> Food
    private var generation = 0

    init(fetch: @escaping @Sendable (Int) async throws -> Food) { self.fetch = fetch }

    func load(fdcID: Int, handedOff: Food? = nil) async {
        generation += 1
        let request = generation
        if let handedOff, handedOff.fdcId == fdcID {
            food = handedOff
            failure = nil
            status = .held
            return
        }
        food = nil
        failure = nil
        status = .looking
        do {
            let result = try await fetch(fdcID)
            guard generation == request else { return }
            food = result
            status = .held
        } catch is CancellationError {
            return
        } catch {
            guard generation == request else { return }
            let error = error as? FoodSearchError
                ?? FoodSearchError("Food lookup is unavailable right now.", kind: .http)
            failure = error
            status = error.status == 404 ? .missing : .failed
        }
    }
}
