import XCTest
import Supabase
@testable import FoodPad

final class RecentFoodsTests: XCTestCase {
    func testNewestSnapshotWinsAndResultIsLimited() {
        let rows = [food(1, "new"), food(1, "old"), food(2, "two"), food(3, "three")]

        let result = RecentFoodsRepository.newestDistinct(rows, limit: 2)

        XCTAssertEqual(result, [food(1, "new"), food(2, "two")])
    }

    func testWidensPastDuplicatesAndRecomputesAfterAnInsert() async throws {
        let duplicates = Array(repeating: food(1, "new"), count: 50)
        let source = ExpandingRecentSource(
            first: duplicates,
            next: [food(4, "inserted")] + duplicates + [food(2, "two"), food(3, "three")]
        )
        let repository = RecentFoodsRepository(
            sessions: SessionCoordinator(auth: RecentAuthStub()), source: source
        )

        let result = try await repository.list()

        XCTAssertEqual(result, [food(4, "inserted"), food(1, "new"), food(2, "two")])
        let limits = await source.limits
        XCTAssertEqual(limits, [50, 100])
    }

    @MainActor
    func testFailureIsSilentRetainsRowsAndRetries() async {
        let reader = FailingRecentReader()
        let existing = food(1, "shown")
        let model = RecentFoodsModel(foods: [existing]) { try await reader.read() }

        await model.load()
        await model.load()

        XCTAssertEqual(model.foods, [existing])
        let readCount = await reader.count
        XCTAssertEqual(readCount, 2)
    }

    func testSupabaseReadIsScopedOrderedAndBounded() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecentURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://project.supabase.co")!, supabaseKey: "test",
            options: .init(global: .init(session: URLSession(configuration: configuration)))
        )
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!

        let rows = try await SupabaseRecentFoodsDataSource(client: client).fetch(userID: userID, limit: 50)

        XCTAssertEqual(rows, [food(7, "1 medium")])
    }

    private func food(_ id: Int, _ serving: String) -> RecentFood {
        RecentFood(fdcID: id, name: "Apple", servingLabel: serving, kcal: 95)
    }
}

private actor FailingRecentReader {
    private(set) var count = 0
    func read() throws -> [RecentFood] { count += 1; throw RecentTestError.failed }
}

private enum RecentTestError: Error { case failed }

private actor ExpandingRecentSource: RecentFoodsDataSource {
    let first: [RecentFood]
    let next: [RecentFood]
    private(set) var limits: [Int] = []

    init(first: [RecentFood], next: [RecentFood]) { self.first = first; self.next = next }

    func fetch(userID: UUID, limit: Int) async throws -> [RecentFood] {
        limits.append(limit)
        return Array((limits.count == 1 ? first : next).prefix(limit))
    }
}

private actor RecentAuthStub: AnonymousAuthClient {
    func validUserID() async throws -> UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000007")! }
    func signInAnonymously() async throws -> UUID { UUID() }
    func clearSession() async {}
    nonisolated func canRecover(from error: Error) -> Bool { false }
}

private final class RecentURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = request.url?.query ?? ""
        guard query.contains("fdc_id%2Cname%2Cserving_label%2Ckcal"),
              query.contains("user_id=eq.00000000-0000-0000-0000-000000000007"),
              query.contains("order=eaten_on.desc.nullslast%2Ccreated_at.desc.nullslast%2Cid.desc.nullslast"),
              query.contains("limit=50") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"[{"fdc_id":7,"name":"Apple","serving_label":"1 medium","kcal":95}]"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
