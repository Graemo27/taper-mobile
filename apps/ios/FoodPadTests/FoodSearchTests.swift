import XCTest
import Supabase
@testable import FoodPad

final class FoodSearchTests: XCTestCase {
    func testSupabaseSourceSendsBothFunctionRoutes() async throws {
        let source = SupabaseFoodSearchDataSource(client: makeClient())

        let result = try await source.search(query: "apple", limit: 5)
        let food = try await source.food(fdcID: 123)

        XCTAssertEqual(result.foods.map(\.name), ["Apple"])
        XCTAssertEqual(result.unavailable, 2)
        XCTAssertEqual(food.name, "Almonds")
    }

    func testSupabaseSourcePreservesHTTPFailureDetails() async {
        let source = SupabaseFoodSearchDataSource(client: makeClient())

        do {
            _ = try await source.search(query: "failure", limit: 5)
            XCTFail("Expected the function failure")
        } catch let error as FoodSearchError {
            XCTAssertEqual(error.kind, .http)
            XCTAssertEqual(error.status, 503)
            XCTAssertEqual(error.requestID, "req-1")
            XCTAssertEqual(error.message, "Lookup failed.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRepositoryTrimsSearchAndRejectsInvalidIDBeforeAuth() async throws {
        let source = FoodSourceStub()
        let repository = FoodSearchRepository(
            sessions: SessionCoordinator(auth: FoodAuthStub()), source: source
        )

        _ = try await repository.search("  apple  ", limit: 99)
        do {
            _ = try await repository.food(fdcID: -1)
            XCTFail("Expected invalid id to be not-found")
        } catch let error as FoodSearchError {
            XCTAssertEqual(error.status, 404)
        }

        let calls = await source.calls
        XCTAssertEqual(calls, [.search("apple", 10)])
    }

    @MainActor
    func testSearchModelDropsAStaleReply() async {
        let old = food(1, "Old")
        let new = food(2, "New")
        let model = SearchModel { query in
            if query == "old" { try await Task.sleep(for: .milliseconds(80)) }
            return FoodSearchResult(foods: [query == "old" ? old : new], unavailable: 0)
        }

        let first = Task { await model.search("old") }
        await Task.yield()
        await model.search("new")
        await first.value

        XCTAssertEqual(model.foods, [new])
        XCTAssertEqual(model.resolvedQuery, "new")
        XCTAssertEqual(model.status, .ready)
    }

    @MainActor
    func testFoodLookupKeepsStateKeyedToTheRequestedID() async {
        let old = food(1, "Old")
        let new = food(2, "New")
        let model = FoodLookupModel { id in
            if id == 1 { try await Task.sleep(for: .milliseconds(80)) }
            return id == 1 ? old : new
        }

        let first = Task { await model.load(fdcID: 1) }
        await Task.yield()
        await model.load(fdcID: 2)
        await first.value

        XCTAssertEqual(model.food, new)
        XCTAssertEqual(model.status, .held)
    }

    private func makeClient() -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FoodSearchURLProtocol.self]
        return SupabaseClient(
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabaseKey: "sb_publishable_test",
            options: .init(
                auth: .init(accessToken: { "test-token" }),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }

    private func food(_ id: Int, _ name: String) -> Food {
        Food(
            fdcId: id, name: name, category: nil, dataType: "Foundation", portion: nil,
            per100g: .empty, perServing: nil, portions: []
        )
    }
}

private actor FoodAuthStub: AnonymousAuthClient {
    func validUserID() async throws -> UUID { UUID() }
    func signInAnonymously() async throws -> UUID { UUID() }
    func clearSession() async {}
    nonisolated func canRecover(from error: Error) -> Bool { false }
}

private actor FoodSourceStub: FoodSearchDataSource {
    enum Call: Equatable { case search(String, Int), food(Int) }
    private(set) var calls: [Call] = []

    func search(query: String, limit: Int) async throws -> FoodSearchResult {
        calls.append(.search(query, limit))
        return FoodSearchResult(foods: [], unavailable: 0)
    }

    func food(fdcID: Int) async throws -> Food {
        calls.append(.food(fdcID))
        throw TestFoodError.failed
    }
}

private enum TestFoodError: Error { case failed }

private final class FoodSearchURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url?.path.hasSuffix("/functions/v1/food-search") == true,
              request.httpMethod == "POST", abs(request.timeoutInterval - 15) < 0.01,
              let body = bodyData(),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let status: Int
        let payload: String
        if json["query"] as? String == "failure" {
            status = 503
            payload = #"{"error":"Lookup failed.","requestId":"req-1"}"#
        } else if json["query"] as? String == "apple", json["limit"] as? Int == 5 {
            status = 200
            payload = #"{"foods":[{"fdcId":1,"name":"Apple","category":null,"dataType":"Foundation","portion":null,"per100g":{"kcal":95,"proteinG":null,"fibreG":null,"vitaminEMg":null,"magnesiumMg":null,"unsaturatedFatG":null},"perServing":null,"portions":[]}],"unavailable":2}"#
        } else if json["fdcId"] as? Int == 123 {
            status = 200
            payload = #"{"food":{"fdcId":123,"name":"Almonds","category":null,"dataType":"Foundation","portion":null,"per100g":{"kcal":null,"proteinG":null,"fibreG":null,"vitaminEMg":null,"magnesiumMg":null,"unsaturatedFatG":null},"perServing":null,"portions":[]}}"#
        } else {
            status = 400
            payload = #"{"error":"Unexpected request"}"#
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func bodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func stopLoading() {}
}
