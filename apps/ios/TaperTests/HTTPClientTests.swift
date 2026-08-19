import XCTest
@testable import Taper

final class HTTPClientTests: XCTestCase {
    func testHTTPClientReturnsNonSuccessResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotFoundURLProtocol.self]
        let client = URLSessionHTTPClient(session: URLSession(configuration: configuration))

        let (data, response) = try await client.send(URLRequest(url: URL(string: "https://example.com")!))

        XCTAssertEqual(response.statusCode, 404)
        XCTAssertEqual(data, Data("missing".utf8))
    }

    func testFaultTransportDelaysOnlyMatchingResponse() async throws {
        let client = URLSessionHTTPClient(session: NetworkSession.live())
        let arguments = ["Taper", "-FPDelay", "0.15", "-FPDelayURL", "select=journal"]

        func duration(for url: URL) async throws -> Duration {
            let request = FaultInjectingURLProtocol.stubbedRequest(url: url, arguments: arguments)
            let start = ContinuousClock.now
            _ = try await client.send(request)
            return start.duration(to: .now)
        }

        let nonmatching = try await duration(for: URL(string: "https://example.com?id=eq.1")!)
        let matching = try await duration(for: URL(string: "https://example.com?select=journal")!)

        XCTAssertGreaterThanOrEqual(matching, .milliseconds(120))
        XCTAssertGreaterThanOrEqual(matching - nonmatching, .milliseconds(100))
    }

    func testFailureAndStatusArgumentsParse() {
        let faults = LaunchFaults(arguments: [
            "Taper", "-FPFail", "food-search", "-FPStatus", "404",
        ])
        XCTAssertEqual(faults.failingURLSubstring, "food-search")
        XCTAssertEqual(faults.status, 404)
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
