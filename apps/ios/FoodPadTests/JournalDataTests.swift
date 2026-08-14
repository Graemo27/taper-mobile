import XCTest
import Supabase
@testable import FoodPad

final class JournalDataTests: XCTestCase {
    func testConcurrentMissingSessionCreatesOneAnonymousUser() async throws {
        let auth = AuthStub(valid: .failure(TestFailure.recoverable))
        let sessions = SessionCoordinator(auth: auth)

        async let first = sessions.userID()
        async let second = sessions.userID()
        _ = try await (first, second)

        let signIns = await auth.signIns
        XCTAssertEqual(signIns, 1)
    }

    func testInvalidRefreshRetriesOriginalOperationOnce() async throws {
        let auth = AuthStub(valid: .success(UUID()))
        let sessions = SessionCoordinator(auth: auth)
        let attempts = AttemptCounter()

        let value = try await sessions.authenticated { _ in try await attempts.run() }

        XCTAssertEqual(value, "ready")
        let count = await attempts.count
        XCTAssertEqual(count, 2)
    }

    func testTruncatedReadDropsOnlyPartialOldestDay() async throws {
        let rows = [entry(1, "2026-08-14"), entry(2, "2026-08-13"), entry(3, "2026-08-13")]
        let repository = makeRepository(page: JournalPage(entries: rows, total: 4))

        let result = try await repository.listEntries()

        XCTAssertEqual(result, [rows[0]])
    }

    func testTruncatedSingleDayIsKept() async throws {
        let rows = [entry(1, "2026-08-14"), entry(2, "2026-08-14")]
        let repository = makeRepository(page: JournalPage(entries: rows, total: 3))

        let result = try await repository.listEntries()
        XCTAssertEqual(result, rows)
    }

    func testWindowContainsThirtyLocalDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!

        XCTAssertEqual(JournalRepository.windowStart(today: today, calendar: calendar), "2026-02-07")
    }

    func testSupabaseReadRequestsExactCountThroughInjectedSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JournalURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabaseKey: "sb_publishable_test",
            options: SupabaseClientOptions(
                auth: .init(accessToken: { "test-token" }),
                global: .init(session: URLSession(configuration: configuration))
            )
        )

        let page = try await SupabaseJournalDataSource(client: client).fetch(
            userID: UUID(), from: "2026-07-16", limit: 2_000
        )

        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.entries.map(\.id), [1])
    }

    private func makeRepository(page: JournalPage) -> JournalRepository {
        JournalRepository(
            sessions: SessionCoordinator(auth: AuthStub(valid: .success(UUID()))),
            source: JournalSourceStub(page: page)
        )
    }

    private func entry(_ id: Int, _ day: String) -> JournalEntry {
        JournalEntry(id: id, eatenOn: day, name: "Food", servingLabel: nil, kcal: nil)
    }
}

private enum TestFailure: Error { case recoverable }

private actor AuthStub: AnonymousAuthClient {
    let valid: Result<UUID, Error>
    private(set) var signIns = 0

    init(valid: Result<UUID, Error>) { self.valid = valid }
    func validUserID() async throws -> UUID { try valid.get() }
    func signInAnonymously() async throws -> UUID {
        signIns += 1
        try await Task.sleep(for: .milliseconds(30))
        return UUID()
    }
    func clearSession() async {}
    nonisolated func canRecover(from error: Error) -> Bool { error is TestFailure }
}

private actor AttemptCounter {
    private(set) var count = 0
    func run() throws -> String {
        count += 1
        if count == 1 { throw TestFailure.recoverable }
        return "ready"
    }
}

private struct JournalSourceStub: JournalDataSource {
    let page: JournalPage
    func fetch(userID: UUID, from start: String, limit: Int) async throws -> JournalPage { page }
}

private final class JournalURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.value(forHTTPHeaderField: "Prefer")?.contains("count=exact") == true,
              request.url?.query?.contains("eaten_on=gte.2026-07-16") == true,
              request.url?.query?.contains("limit=2000") == true else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let data = Data(#"[{"id":1,"eaten_on":"2026-08-14","name":"Food","serving_label":null,"kcal":null}]"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 206, httpVersion: nil,
            headerFields: ["Content-Range": "0-0/3", "Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
