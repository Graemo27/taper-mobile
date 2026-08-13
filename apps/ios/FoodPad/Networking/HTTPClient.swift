import Foundation

protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

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

enum NetworkSession {
    /// Use this session for both `HTTPClient` and Supabase so launch faults cover every request.
    static func live() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [FaultInjectingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

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

private final class FaultInjectingURLProtocol: URLProtocol, @unchecked Sendable {
    private var transportTask: URLSessionDataTask?
    private let loading = LoadingGate()

    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let faults = LaunchFaults()
        if let substring = faults.failingURLSubstring,
           request.url?.absoluteString.contains(substring) == true {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        transportTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
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

            // The real response has arrived; delaying here preserves the stale-response ordering.
            let delay = faults.delay(for: self.request.url)
            self.loading.schedule(after: delay, finish)
        }
        transportTask?.resume()
    }

    override func stopLoading() {
        transportTask?.cancel()
        transportTask = nil
        loading.cancel()
    }
}
