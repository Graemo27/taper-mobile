import Foundation
import Supabase

struct FoodSearchResult: Decodable, Equatable, Sendable {
    let foods: [Food]
    let unavailable: Int
}

struct FoodSearchError: Error, Equatable, LocalizedError, Sendable {
    enum Kind: Equatable, Sendable { case http, timeout, offline }

    let message: String
    let kind: Kind
    let status: Int?
    let requestID: String?

    init(_ message: String, kind: Kind, status: Int? = nil, requestID: String? = nil) {
        self.message = message
        self.kind = kind
        self.status = status
        self.requestID = requestID
    }

    var errorDescription: String? { message }
}

protocol FoodSearchDataSource: Sendable {
    func search(query: String, limit: Int) async throws -> FoodSearchResult
    func food(fdcID: Int) async throws -> Food
}

struct SupabaseFoodSearchDataSource: FoodSearchDataSource {
    let client: SupabaseClient

    func search(query: String, limit: Int) async throws -> FoodSearchResult {
        try await invoke(SearchRequest(query: query, limit: limit))
    }

    func food(fdcID: Int) async throws -> Food {
        let response: FoodResponse = try await invoke(FoodRequest(fdcId: fdcID))
        return response.food
    }

    private func invoke<Response: Decodable>(_ body: some Encodable) async throws -> Response {
        do {
            return try await client.functions.invoke(
                "food-search", options: .init(body: body, timeoutInterval: 15)
            )
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> FoodSearchError {
        if let error = error as? FunctionsError {
            switch error {
            case let .httpError(code, data):
                let payload = try? JSONDecoder().decode(FailureResponse.self, from: data)
                return FoodSearchError(
                    payload?.error.nilIfEmpty ?? "Food lookup is unavailable right now.",
                    kind: .http, status: code, requestID: payload?.requestId
                )
            case .relayError:
                return FoodSearchError("Food lookup is unavailable right now.", kind: .http)
            }
        }
        if let error = error as? URLError {
            return error.code == .timedOut
                ? FoodSearchError("Food search took too long.", kind: .timeout)
                : FoodSearchError("Could not reach food search. Check your connection.", kind: .offline)
        }
        if error is DecodingError {
            return FoodSearchError("Food lookup is unavailable right now.", kind: .http)
        }
        return FoodSearchError("Could not reach food search. Check your connection.", kind: .offline)
    }

    private struct SearchRequest: Encodable { let query: String; let limit: Int }
    private struct FoodRequest: Encodable { let fdcId: Int }
    private struct FoodResponse: Decodable { let food: Food }
    private struct FailureResponse: Decodable { let error: String?; let requestId: String? }
}

struct FoodSearchRepository: Sendable {
    let sessions: SessionCoordinator
    let source: any FoodSearchDataSource

    func search(_ query: String, limit: Int = 5) async throws -> FoodSearchResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return FoodSearchResult(foods: [], unavailable: 0) }
        let limit = min(10, max(1, limit))
        return try await sessions.authenticated { _ in
            try await source.search(query: query, limit: limit)
        }
    }

    func food(fdcID: Int) async throws -> Food {
        guard fdcID > 0 else {
            throw FoodSearchError("That food could not be found.", kind: .http, status: 404)
        }
        return try await sessions.authenticated { _ in try await source.food(fdcID: fdcID) }
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? { flatMap { $0.isEmpty ? nil : $0 } }
}
