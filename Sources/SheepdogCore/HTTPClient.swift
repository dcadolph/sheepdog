import Foundation

// HTTPClient sends one request and returns the body and status code.
public protocol HTTPClient: Sendable {
    // send performs the request.
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

// HTTPClientFunc adapts a function to HTTPClient.
public struct HTTPClientFunc: HTTPClient {
    // fn performs the request.
    let fn: @Sendable (URLRequest) async throws -> (Data, Int)

    // init wraps fn.
    public init(_ fn: @escaping @Sendable (URLRequest) async throws -> (Data, Int)) {
        self.fn = fn
    }

    // send calls the wrapped function.
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await fn(request)
    }
}

// URLSessionClient sends requests through a URLSession.
public struct URLSessionClient: HTTPClient {
    // session performs the requests.
    let session: URLSession

    // init uses the given session, or the shared one.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // send performs the request and reports a status of 0 for non-HTTP responses.
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

// checkStatus maps a calendar API status code to an error, or returns for success.
func checkStatus(_ status: Int) throws {
    switch status {
    case 200..<300:
        return
    case 401:
        throw RemoteError.unauthorized
    default:
        throw RemoteError.server(status: status)
    }
}

// bearerRequest builds a GET request authorized with an access token.
func bearerRequest(_ url: URL, accessToken: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
}

// basicRequest builds a GET request authorized with a user name and password.
func basicRequest(_ url: URL, username: String, password: String) -> URLRequest {
    var request = URLRequest(url: url)
    let token = Data("\(username):\(password)".utf8).base64EncodedString()
    request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    return request
}

// maxPages bounds paging so a misbehaving service cannot loop forever.
let maxPages = 25
