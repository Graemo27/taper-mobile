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

    func testJournalDatesStayGregorianForNonGregorianUserCalendar() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let today = gregorian.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12))!
        var userCalendar = Calendar(identifier: .buddhist)
        userCalendar.timeZone = gregorian.timeZone

        XCTAssertEqual(JournalRepository.windowStart(today: today, calendar: userCalendar), "2026-07-16")
        XCTAssertEqual(JournalRepository.localDate(today, calendar: userCalendar), "2026-08-14")
    }

    func testSaveWritesTheDisplayedSnapshotOnTheLocalDate() async throws {
        let source = JournalWriteStub()
        let userID = UUID()
        let repository = JournalWriteRepository(
            sessions: SessionCoordinator(auth: AuthStub(valid: .success(userID))), source: source
        )
        let draft = saveDraft(7)

        try await repository.save(draft, at: date(2026, 8, 14), calendar: testCalendar)

        let call = await source.call
        XCTAssertEqual(call, .init(userID: userID, eatenOn: "2026-08-14", draft: draft))
    }

    @MainActor
    func testSaveStateStaysKeyedWhenAnOlderFailureArrives() async {
        let model = FoodSaveModel(
            save: { draft in
                if draft.fdcID == 1 {
                    try await Task.sleep(for: .milliseconds(50))
                    throw TestFailure.recoverable
                }
            },
            holdConfirmation: { try? await Task.sleep(for: .seconds(1)) }
        )
        let old = Task { await model.save(saveDraft(1)) }
        await Task.yield()
        let current = Task { await model.save(saveDraft(2)) }
        while model.status(for: 2) != .saved { await Task.yield() }

        await old.value

        XCTAssertEqual(model.status(for: 2), .saved)
        current.cancel()
    }

    @MainActor
    func testChangingTheServingClearsItsConfirmation() async {
        let model = FoodSaveModel(
            save: { _ in }, holdConfirmation: { try? await Task.sleep(for: .seconds(1)) }
        )
        let saving = Task { await model.save(saveDraft(1)) }
        while model.status(for: 1) != .saved { await Task.yield() }

        model.reset(for: 1)

        XCTAssertEqual(model.status(for: 1), .idle)
        saving.cancel()
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

    func testSupabaseSaveSendsTheSnapshotFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JournalURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabaseKey: "sb_publishable_test",
            options: .init(global: .init(session: URLSession(configuration: configuration)))
        )

        try await SupabaseJournalWriteDataSource(client: client).save(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            eatenOn: "2026-08-14", draft: saveDraft(7)
        )
    }

    func testPresentationGroupsInQueryOrderAndNamesRelativeDays() {
        let rows = [entry(1, "2026-08-14"), entry(3, "2026-08-13"), entry(2, "2026-08-14")]

        let days = JournalPresentation.days(from: rows)

        XCTAssertEqual(days.map(\.date), ["2026-08-14", "2026-08-13"])
        XCTAssertEqual(days.map { $0.entries.map(\.id) }, [[1, 2], [3]])
        XCTAssertEqual(JournalPresentation.heading(for: days[0].date, today: "2026-08-14"), "Today")
        XCTAssertEqual(JournalPresentation.heading(for: days[1].date, today: "2026-08-14"), "Yesterday")
        XCTAssertEqual(
            JournalPresentation.heading(
                for: "2026-08-09", today: "2026-08-14", locale: Locale(identifier: "en_US")
            ),
            "Sunday, August 9"
        )
        XCTAssertEqual(JournalPresentation.thingCount(2), "2 things")
    }

    @MainActor
    func testFailedRefreshKeepsPreviouslyRenderedDays() async {
        let rows = [entry(1, "2026-08-14")]
        let model = JournalModel(entries: rows, today: "2026-08-14") { throw TestFailure.recoverable }

        await model.load()

        XCTAssertEqual(model.entries, rows)
        XCTAssertEqual(model.status, .failed)
    }

    @MainActor
    func testMidnightClockRearmsForFollowingDay() async {
        let clock = MidnightStub(dates: [date(2026, 8, 15), date(2026, 8, 16)])
        let model = JournalModel(today: "2026-08-14") { [] }

        await model.followMidnights(clock: clock, calendar: testCalendar)

        XCTAssertEqual(model.today, "2026-08-16")
        let calls = await clock.calls
        XCTAssertEqual(calls, 3)
    }

    @MainActor
    func testMidnightClockCorrectsDateBeforeWaiting() async {
        let model = JournalModel(today: "stale") { [] }
        await model.followMidnights(
            clock: MidnightStub(dates: []), calendar: testCalendar, startingAt: date(2026, 8, 14)
        )

        XCTAssertEqual(model.today, "2026-08-14")
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

    private func saveDraft(_ id: Int) -> JournalDraft {
        JournalDraft(
            fdcID: id, name: "Apple", servingLabel: "2 medium · 364 g", servings: 2,
            grams: 364, kcal: 189, proteinG: 1.1, fibreG: 8.7
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 0, second: 1))!
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

private actor JournalWriteStub: JournalWriteDataSource {
    struct Call: Equatable {
        let userID: UUID
        let eatenOn: String
        let draft: JournalDraft
    }

    private(set) var call: Call?
    func save(userID: UUID, eatenOn: String, draft: JournalDraft) {
        call = Call(userID: userID, eatenOn: eatenOn, draft: draft)
    }
}

private actor MidnightStub: MidnightClock {
    private var dates: [Date]
    private(set) var calls = 0

    init(dates: [Date]) { self.dates = dates }

    func nextMidnight(after date: Date, calendar: Calendar) throws -> Date {
        calls += 1
        guard !dates.isEmpty else { throw CancellationError() }
        return dates.removeFirst()
    }
}

private final class JournalURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.httpMethod == "POST", let data = bodyData(),
           let json = try? JSONSerialization.jsonObject(with: data),
           let row = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first,
           row["user_id"] as? String == "00000000-0000-0000-0000-000000000007",
           row["eaten_on"] as? String == "2026-08-14", row["fdc_id"] as? Int == 7,
           row["serving_label"] as? String == "2 medium · 364 g",
           row["servings"] as? Int == 2, row["kcal"] as? Int == 189 {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("[]".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
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
    private func bodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1_024)
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
