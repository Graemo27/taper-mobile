import XCTest
import Supabase
@testable import FoodPad

final class FavouritesTests: XCTestCase {
    func testSupabaseSourceScopesReadsAndWritesAndIgnoresDuplicateAdds() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavouritesURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://project.supabase.co")!, supabaseKey: "test",
            options: .init(global: .init(session: URLSession(configuration: configuration)))
        )
        let source = SupabaseFavouritesDataSource(client: client)
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!

        let ids = try await source.list(userID: userID)
        XCTAssertEqual(ids, [7])
        try await source.add(userID: userID, fdcID: 7)
        try await source.remove(userID: userID, fdcID: 7)
    }

    @MainActor
    func testPressDuringLoadWinsOverStaleResponse() async {
        let gate = ValueGate<Set<Int>>()
        let model = FavouritesModel(read: { await gate.wait() }, persist: { _, _ in })
        let loading = Task { await model.load() }
        await Task.yield()

        await model.toggle(7)
        await gate.open([1])
        await loading.value

        XCTAssertEqual(model.ids, [1, 7])
    }

    @MainActor
    func testRapidPressesPersistInOrder() async {
        let firstWrite = ValueGate<Void>()
        let writes = WriteRecorder(gate: firstWrite)
        let model = FavouritesModel(read: { [] }, persist: { on, id in
            await writes.record(on, id: id)
        })

        let first = Task { await model.toggle(7) }
        while await writes.values.isEmpty { await Task.yield() }
        let second = Task { await model.toggle(7) }
        await firstWrite.open(())
        await first.value
        await second.value

        let values = await writes.values
        XCTAssertEqual(values, [true, false])
        XCTAssertFalse(model.ids.contains(7))
    }

    @MainActor
    func testFailedWriteRollsBackAndFailedLoadRetries() async {
        let reads = RetryReader()
        let model = FavouritesModel(
            read: { try await reads.read() },
            persist: { _, _ in throw TestError.failed }
        )

        await model.load()
        await model.load()
        await model.toggle(7)

        let count = await reads.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(model.ids, [1])
    }
}

private actor ValueGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var stored: Value?

    func wait() async -> Value {
        if let stored { return stored }
        return await withCheckedContinuation { continuation = $0 }
    }

    func open(_ value: Value) {
        if let continuation { continuation.resume(returning: value) }
        else { stored = value }
    }
}

private actor WriteRecorder {
    private(set) var values: [Bool] = []
    let gate: ValueGate<Void>
    init(gate: ValueGate<Void>) { self.gate = gate }

    func record(_ on: Bool, id: Int) async {
        values.append(on)
        if values.count == 1 { await gate.wait() }
    }
}

private actor RetryReader {
    private(set) var count = 0
    func read() throws -> Set<Int> {
        count += 1
        if count == 1 { throw TestError.failed }
        return [1]
    }
}

private enum TestError: Error { case failed }

private final class FavouritesURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = request.url?.query ?? ""
        let valid: Bool
        let data: Data
        switch request.httpMethod {
        case "GET":
            valid = query.contains("user_id=eq.00000000-0000-0000-0000-000000000007")
            data = Data(#"[{"fdc_id":7}]"#.utf8)
        case "POST":
            valid = query.contains("on_conflict=user_id%2Cfdc_id")
                && request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=ignore-duplicates") == true
            data = Data("[]".utf8)
        case "DELETE":
            valid = query.contains("user_id=eq.00000000-0000-0000-0000-000000000007")
                && query.contains("fdc_id=eq.7")
            data = Data("[]".utf8)
        default: valid = false; data = Data()
        }
        guard valid else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
