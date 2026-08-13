import XCTest
@testable import FoodPad

final class FoodPadTests: XCTestCase {
    func testHTTPClientReturnsNonSuccessResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotFoundURLProtocol.self]
        let client = URLSessionHTTPClient(session: URLSession(configuration: configuration))

        let (data, response) = try await client.send(URLRequest(url: URL(string: "https://example.com")!))

        XCTAssertEqual(response.statusCode, 404)
        XCTAssertEqual(data, Data("missing".utf8))
    }

    func testGlobalResponseDelayParses() {
        let faults = LaunchFaults(arguments: ["FoodPad", "-FPDelay", "0.05"])
        XCTAssertEqual(faults.delay(for: URL(string: "https://example.com/foods")), 0.05)
    }

    func testScopedResponseDelayMatchesURL() {
        let faults = LaunchFaults(arguments: [
            "FoodPad", "-FPDelay", "0.05", "-FPDelayURL", "select=journal",
        ])
        XCTAssertEqual(faults.delay(for: URL(string: "https://example.com?select=journal")), 0.05)
    }

    func testScopedResponseDelayLeavesOtherURLsUndelayed() {
        let faults = LaunchFaults(arguments: [
            "FoodPad", "-FPDelay", "0.05", "-FPDelayURL", "select=journal",
        ])
        XCTAssertEqual(faults.delay(for: URL(string: "https://example.com?id=eq.1")), 0)
    }

    func testFailureAndStatusArgumentsParse() {
        let faults = LaunchFaults(arguments: [
            "FoodPad", "-FPFail", "food-search", "-FPStatus", "404",
        ])
        XCTAssertEqual(faults.failingURLSubstring, "food-search")
        XCTAssertEqual(faults.status, 404)
    }

    func testResponseDeliveryWaitsForConfiguredDelay() {
        let delivered = expectation(description: "response delivered")
        let start = ContinuousClock.now
        let loading = LoadingGate()

        loading.schedule(after: 0.05) { delivered.fulfill() }

        wait(for: [delivered], timeout: 0.2)
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(40))
    }

    func testCancellationStopsDelayedDelivery() {
        let delivered = expectation(description: "response delivered")
        delivered.isInverted = true
        let loading = LoadingGate()

        loading.schedule(after: 0.05) { delivered.fulfill() }
        loading.cancel()

        wait(for: [delivered], timeout: 0.1)
    }
}

private final class NotFoundURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("missing".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
