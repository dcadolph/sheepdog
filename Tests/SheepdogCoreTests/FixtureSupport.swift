import Foundation

@testable import SheepdogCore

// fixture returns the bytes of a file in the Fixtures directory.
func fixture(_ name: String) -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
          let data = try? Data(contentsOf: url)
    else {
        fatalError("missing fixture \(name)")
    }
    return data
}

// utc parses an RFC 3339 time in tests.
func utc(_ text: String) -> Date {
    try! Date.ISO8601FormatStyle().parse(text)
}

// MockResponse is a canned reply for one request.
struct MockResponse: Sendable {
    // Body is the response body.
    let body: Data
    // Status is the HTTP status code.
    let status: Int

    // ok replies 200 with a fixture body.
    static func ok(_ name: String) -> MockResponse {
        MockResponse(body: fixture(name), status: 200)
    }

    // json replies with an inline body and status.
    static func json(_ text: String, status: Int = 200) -> MockResponse {
        MockResponse(body: Data(text.utf8), status: status)
    }
}

// MockClient answers requests from a route function and records every request it sees.
final class MockClient: HTTPClient, @unchecked Sendable {
    // route picks the reply for a request.
    private let route: @Sendable (URLRequest, Int) -> MockResponse
    // lock guards requests.
    private let lock = NSLock()
    // recorded holds every request in order.
    private var recorded: [URLRequest] = []

    // init creates a client. The route receives the request and how many requests came before it.
    init(route: @escaping @Sendable (URLRequest, Int) -> MockResponse) {
        self.route = route
    }

    // requests returns every request sent so far.
    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    // reply returns the routed reply for a request without recording it.
    func reply(_ request: URLRequest) -> MockResponse {
        route(request, -1)
    }

    // send records the request and returns the routed reply.
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let count = lock.withLock {
            recorded.append(request)
            return recorded.count - 1
        }
        let reply = route(request, count)
        return (reply.body, reply.status)
    }
}

// TestClock is a settable clock for token expiry tests.
final class TestClock: @unchecked Sendable {
    // lock guards current.
    private let lock = NSLock()
    // current is the time the clock reports.
    private var current: Date

    // init starts the clock at a time.
    init(_ start: Date) {
        current = start
    }

    // now returns the current time.
    func now() -> Date {
        lock.withLock { current }
    }

    // advance moves the clock forward.
    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

// queryItems returns a URL's query as a dictionary for order-free comparison.
func queryItems(_ url: URL?) -> [String: String] {
    let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

// bodyText returns a request body as text.
func bodyText(_ request: URLRequest) -> String {
    request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
}
