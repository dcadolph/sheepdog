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

    // init uses an ephemeral session that answers the server's Basic or NTLM challenge with the user name
    // and password. Nothing is cached on disk, and no other host is ever given the password.
    public init(server: URL, username: String, password: String) {
        let delegate = CredentialDelegate(
            server: server, credential: URLCredential(user: username, password: password, persistence: .none)
        )
        self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    // send performs the request and reports a status of 0 for non-HTTP responses.
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

// CredentialDelegate answers authentication challenges from one server with one credential.
final class CredentialDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    // server is the only origin that gets the credential.
    let server: URL
    // credential is the user name and password.
    let credential: URLCredential

    // init creates a delegate for a server.
    init(server: URL, credential: URLCredential) {
        self.server = server
        self.credential = credential
    }

    // answer decides a challenge. Basic and NTLM from the server's own scheme, host and port get the
    // credential once. A second challenge means the password was refused, so the protection space is
    // rejected and the 401 comes back to the caller. Negotiate is rejected so the server falls back to NTLM,
    // and anything else, such as the server's certificate, gets the system's default handling.
    func answer(_ space: URLProtectionSpace, previousFailureCount: Int) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodNTLM:
            guard matches(space) else {
                return (.performDefaultHandling, nil)
            }
            if previousFailureCount > 0 {
                return (.rejectProtectionSpace, nil)
            }
            return (.useCredential, credential)
        case NSURLAuthenticationMethodNegotiate:
            return (.rejectProtectionSpace, nil)
        default:
            return (.performDefaultHandling, nil)
        }
    }

    // matches reports a protection space on the server's scheme, host and port.
    func matches(_ space: URLProtectionSpace) -> Bool {
        guard let scheme = server.scheme?.lowercased(), let host = server.host?.lowercased() else {
            return false
        }
        let port = server.port ?? (scheme == "https" ? 443 : 80)
        return space.protocol?.lowercased() == scheme && space.host.lowercased() == host && space.port == port
    }

    // urlSession answers a task's authentication challenge.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let (disposition, credential) = answer(
            challenge.protectionSpace, previousFailureCount: challenge.previousFailureCount
        )
        completionHandler(disposition, credential)
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
