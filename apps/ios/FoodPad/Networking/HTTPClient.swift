import Foundation

/// The transport seam. Returns every received HTTP response, including 4xx
/// and 5xx; throws only when no HTTP response exists.
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession` behind the seam, on the fault-injectable session.
struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession = NetworkSession.live()) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

/// The session every network path shares.
enum NetworkSession {
    /// Use this session for both `HTTPClient` and Supabase so launch faults cover every request.
    static func live() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [FaultInjectingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// Fault injection parsed from launch arguments: a delay (optionally scoped
/// to URLs containing a substring), a failing URL, a forced status.
struct LaunchFaults {
    let delay: TimeInterval
    let delayedURLSubstring: String?
    let failingURLSubstring: String?
    let status: Int?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        delay = max(0, Double(value(after: "-FPDelay") ?? "") ?? 0)
        delayedURLSubstring = value(after: "-FPDelayURL")
        failingURLSubstring = value(after: "-FPFail")
        status = value(after: "-FPStatus")
            .flatMap(Int.init)
            .flatMap { (100...599).contains($0) ? $0 : nil }
    }

    func delay(for url: URL?) -> TimeInterval {
        let matchesScope = delayedURLSubstring.map {
            url?.absoluteString.contains($0) == true
        } ?? true
        return matchesScope ? delay : 0
    }
}

/// Guards delayed delivery so a cancelled load can never deliver callbacks
/// after cancellation.
final class LoadingGate: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var active = true
    private var delayedWork: DispatchWorkItem?

    func schedule(after delay: TimeInterval, _ delivery: @escaping @Sendable () -> Void) {
        let work = DispatchWorkItem(block: delivery)
        lock.lock()
        guard active else { lock.unlock(); return }
        delayedWork = work
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }

    func performIfActive(_ callback: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        callback()
    }

    func cancel() {
        lock.lock()
        active = false
        delayedWork?.cancel()
        delayedWork = nil
        lock.unlock()
    }
}

/// The URL protocol that applies `LaunchFaults` at the transport boundary,
/// where the real requests actually travel.
final class FaultInjectingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let argumentsKey = "FoodPad.faultArguments"
    private static let stubKey = "FoodPad.stubResponse"
    private var transportTask: URLSessionDataTask?
    private let loading = LoadingGate()

    static func stubbedRequest(url: URL, arguments: [String]) -> URLRequest {
        let request = NSMutableURLRequest(url: url)
        URLProtocol.setProperty(arguments, forKey: argumentsKey, in: request)
        URLProtocol.setProperty(true, forKey: stubKey, in: request)
        return request as URLRequest
    }

    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let arguments = URLProtocol.property(forKey: Self.argumentsKey, in: request) as? [String]
        let faults = LaunchFaults(arguments: arguments ?? ProcessInfo.processInfo.arguments)
        if let substring = faults.failingURLSubstring,
           request.url?.absoluteString.contains(substring) == true {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        if URLProtocol.property(forKey: Self.stubKey, in: request) as? Bool == true {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            deliver(Data("stub".utf8), response: response, error: nil, faults: faults)
            return
        }

        transportTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.deliver(data, response: response, error: error, faults: faults)
        }
        transportTask?.resume()
    }

    private func deliver(
        _ data: Data?, response: URLResponse?, error: Error?, faults: LaunchFaults
    ) {
        let finish: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
                if let error {
                    self.loading.performIfActive {
                        self.client?.urlProtocol(self, didFailWithError: error)
                    }
                    return
                }
                guard let response else {
                    self.loading.performIfActive {
                        self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                    }
                    return
                }
                let delivered = faults.status.flatMap { status in
                    guard let http = response as? HTTPURLResponse, let url = http.url else { return nil }
                    return HTTPURLResponse(
                        url: url,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: http.allHeaderFields as? [String: String]
                    )
                } ?? response
                self.loading.performIfActive {
                    self.client?.urlProtocol(self, didReceive: delivered, cacheStoragePolicy: .notAllowed)
                }
                if let data {
                    self.loading.performIfActive { self.client?.urlProtocol(self, didLoad: data) }
                }
                self.loading.performIfActive { self.client?.urlProtocolDidFinishLoading(self) }
        }

        // The response has arrived; delaying here preserves the stale-response ordering.
        loading.schedule(after: faults.delay(for: request.url), finish)
    }

    override func stopLoading() {
        transportTask?.cancel()
        transportTask = nil
        loading.cancel()
    }
}
