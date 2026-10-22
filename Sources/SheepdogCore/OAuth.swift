import Foundation

// AccountKind names a calendar service Sheepdog can sign in to.
public enum AccountKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case microsoft
    case google

    // id identifies the kind in lists.
    public var id: String { rawValue }

    // label is the service's user-facing name.
    public var label: String {
        switch self {
        case .microsoft:
            return "Microsoft 365 or Outlook.com"
        case .google:
            return "Google"
        }
    }
}

// OAuthProvider is one service's endpoints plus the app's registration with it.
public struct OAuthProvider: Sendable, Equatable {
    // Kind is the service.
    public var kind: AccountKind
    // ClientID is the app's public client id from the service's app registration.
    public var clientID: String
    // ClientSecret is sent by Google desktop clients. Google documents it as not confidential.
    public var clientSecret: String?
    // AuthorizeURL is where the browser signs the user in.
    public var authorizeURL: URL
    // TokenURL exchanges codes and refresh tokens for access tokens.
    public var tokenURL: URL
    // Scopes are the permissions requested.
    public var scopes: [String]
    // RedirectHost is the loopback host the service expects in the redirect URI.
    public var redirectHost: String
    // ExtraParameters are added to the authorization URL.
    public var extraParameters: [URLQueryItem]

    // microsoft returns the Microsoft identity platform provider for any work, school or personal account.
    public static func microsoft(clientID: String) -> OAuthProvider {
        OAuthProvider(
            kind: .microsoft,
            clientID: clientID,
            clientSecret: nil,
            authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            scopes: ["offline_access", "User.Read", "Calendars.Read"],
            redirectHost: "localhost",
            extraParameters: [URLQueryItem(name: "prompt", value: "select_account")]
        )
    }

    // google returns the Google provider with read-only calendar access and a refresh token.
    public static func google(clientID: String, clientSecret: String?) -> OAuthProvider {
        OAuthProvider(
            kind: .google,
            clientID: clientID,
            clientSecret: clientSecret,
            authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            scopes: ["https://www.googleapis.com/auth/calendar.readonly"],
            redirectHost: "127.0.0.1",
            extraParameters: [
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]
        )
    }

    // redirectURI is the loopback address the browser returns to.
    public func redirectURI(port: UInt16) -> String {
        "http://\(redirectHost):\(port)"
    }

    // authorizationURL is the page the system browser opens to sign the user in.
    public func authorizationURL(pkce: PKCE, state: String, redirectURI: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ] + extraParameters
        return components.url!
    }

    // tokenRequest exchanges an authorization code for tokens.
    public func tokenRequest(code: String, pkce: PKCE, redirectURI: String) -> URLRequest {
        formRequest([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("code_verifier", pkce.verifier),
        ])
    }

    // refreshRequest trades a refresh token for a new access token.
    public func refreshRequest(refreshToken: String) -> URLRequest {
        var fields = [("grant_type", "refresh_token"), ("refresh_token", refreshToken)]
        if kind == .microsoft {
            fields.append(("scope", scopes.joined(separator: " ")))
        }
        return formRequest(fields)
    }

    // formRequest builds a form-encoded POST to the token endpoint with the client credentials.
    private func formRequest(_ fields: [(String, String)]) -> URLRequest {
        var all = [("client_id", clientID)] + fields
        if let clientSecret, !clientSecret.isEmpty {
            all.append(("client_secret", clientSecret))
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(formEncode(all).utf8)
        return request
    }
}

// formEncode encodes fields as application/x-www-form-urlencoded, escaping all but unreserved characters.
func formEncode(_ fields: [(String, String)]) -> String {
    fields.map { "\(percentEncode($0.0))=\(percentEncode($0.1))" }.joined(separator: "&")
}

// percentEncode escapes every character outside the RFC 3986 unreserved set.
func percentEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

// TokenSet is the tokens from one successful token response.
public struct TokenSet: Sendable, Equatable {
    // AccessToken authorizes API calls until it expires.
    public var accessToken: String
    // RefreshToken renews the access token, when the response included one.
    public var refreshToken: String?
    // ExpiresAt is when the access token stops working.
    public var expiresAt: Date

    // init creates a token set.
    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    // decode reads a token endpoint response, mapping OAuth errors to AuthError.
    public static func decode(_ data: Data, status: Int, now: Date) throws -> TokenSet {
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            if let code = body?.error, reauthorizeCodes.contains(code) {
                throw AuthError.reauthorize(body?.errorDescription ?? code)
            }
            throw AuthError.server(status: status, code: body?.error)
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), !body.accessToken.isEmpty else {
            throw AuthError.decode
        }
        return TokenSet(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(body.expiresIn ?? 3600))
        )
    }

    // reauthorizeCodes are OAuth error codes that only a new sign-in fixes.
    private static let reauthorizeCodes: Set<String> = [
        "invalid_grant", "interaction_required", "consent_required", "login_required",
    ]

    // Body is a successful token response.
    private struct Body: Decodable {
        // AccessToken is the bearer token.
        let accessToken: String
        // RefreshToken is present on code exchange and, for Microsoft, on every refresh.
        let refreshToken: String?
        // ExpiresIn is the access token lifetime in seconds.
        let expiresIn: Int?

        // CodingKeys maps the snake case field names.
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    // ErrorBody is an OAuth error response.
    private struct ErrorBody: Decodable {
        // Error is the OAuth error code.
        let error: String
        // ErrorDescription is the service's explanation.
        let errorDescription: String?

        // CodingKeys maps the snake case field names.
        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }
}

// AuthorizationCallback reads what the browser delivered to the loopback redirect.
public enum AuthorizationCallback {
    // target returns the request target from the first line of an HTTP GET, such as "/?code=x&state=y".
    public static func target(fromRequest data: Data) -> String? {
        guard let text = String(data: data.prefix(8192), encoding: .utf8),
              let line = text.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else {
            return nil
        }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/") else {
            return nil
        }
        return String(parts[1])
    }

    // code returns the authorization code from a redirect target after checking its state.
    // It returns nil for requests that are not the redirect, such as the browser asking for a favicon.
    public static func code(fromTarget target: String, expectedState: String) throws -> String? {
        guard let components = URLComponents(string: target), components.path == "/" || components.path.isEmpty else {
            return nil
        }
        let items = components.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        let code = value("code")
        let error = value("error")
        if code == nil && error == nil {
            return nil
        }
        guard value("state") == expectedState else {
            throw AuthError.stateMismatch
        }
        if let error {
            let reason = value("error_description")?.replacingOccurrences(of: "+", with: " ")
            throw AuthError.denied(reason ?? error)
        }
        guard let code, !code.isEmpty else {
            throw AuthError.denied("no authorization code")
        }
        return code
    }
}
