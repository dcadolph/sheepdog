import Foundation

// AccountRecord is what Sheepdog stores in the Keychain for one signed-in account.
public struct AccountRecord: Sendable, Codable, Equatable, CustomStringConvertible {
    // Credential is the secret that keeps an account signed in. It is only ever written to the Keychain.
    public enum Credential: Sendable, Equatable, CustomStringConvertible {
        // refreshToken renews access tokens for a browser sign-in.
        case refreshToken(String)
        // password signs in to a server with a user name and password, such as an app-specific password.
        case password(server: URL, username: String, password: String)

        // description names the form with every secret redacted.
        public var description: String {
            switch self {
            case .refreshToken:
                return "refreshToken(<redacted>)"
            case .password(let server, let username, _):
                return "password(server: \(server.absoluteString), username: \(username), password: <redacted>)"
            }
        }
    }

    // Kind is the service.
    public var kind: AccountKind
    // Address is the account's mail address, shown in settings.
    public var address: String?
    // Credential keeps the account signed in.
    public var credential: Credential

    // init creates a record.
    public init(kind: AccountKind, address: String?, credential: Credential) {
        self.kind = kind
        self.address = address
        self.credential = credential
    }

    // init creates a record for a browser sign-in.
    public init(kind: AccountKind, address: String?, refreshToken: String) {
        self.init(kind: kind, address: address, credential: .refreshToken(refreshToken))
    }

    // refreshToken returns the refresh token of a browser sign-in.
    public var refreshToken: String? {
        if case .refreshToken(let token) = credential {
            return token
        }
        return nil
    }

    // description identifies the account with the credential redacted, so logging a record never leaks it.
    public var description: String {
        "AccountRecord(kind: \(kind.rawValue), address: \(address ?? "nil"), credential: \(credential))"
    }

    // CodingKeys are the flat JSON keys. A browser sign-in has refreshToken, a password sign-in has the other three.
    enum CodingKeys: String, CodingKey {
        case kind, address, refreshToken, server, username, password
    }

    // init decodes a record from either credential form.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(AccountKind.self, forKey: .kind)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        if let token = try container.decodeIfPresent(String.self, forKey: .refreshToken) {
            credential = .refreshToken(token)
        } else {
            credential = .password(
                server: try container.decode(URL.self, forKey: .server),
                username: try container.decode(String.self, forKey: .username),
                password: try container.decode(String.self, forKey: .password)
            )
        }
    }

    // encode writes the record with the keys of its credential form.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(address, forKey: .address)
        switch credential {
        case .refreshToken(let token):
            try container.encode(token, forKey: .refreshToken)
        case .password(let server, let username, let password):
            try container.encode(server, forKey: .server)
            try container.encode(username, forKey: .username)
            try container.encode(password, forKey: .password)
        }
    }
}

// AccountSession reads one connected account's events.
public protocol AccountSession: Actor {
    // record is the stored account.
    var record: AccountRecord { get }

    // entries reads events in the window.
    func entries(from: Date, to: Date) async throws -> [CalendarEntry]
}

// SignIn finishes a browser sign-in once the redirect has delivered a code.
public enum SignIn {
    // complete exchanges the code for tokens and finds the account's address.
    public static func complete(
        provider: OAuthProvider, code: String, pkce: PKCE, redirectURI: String, client: HTTPClient, now: Date
    ) async throws -> AccountRecord {
        let request = provider.tokenRequest(code: code, pkce: pkce, redirectURI: redirectURI)
        let (data, status) = try await client.send(request)
        let tokens = try TokenSet.decode(data, status: status, now: now)
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            throw AuthError.noRefreshToken
        }
        let address: String?
        switch provider.kind {
        case .microsoft:
            address = IDToken.email(tokens.idToken)
        case .google:
            address = try await GoogleCalendar.profile(client: client, accessToken: tokens.accessToken)
        case .icloud, .caldav, .exchange:
            throw AuthError.refused(.other(code: "not_browser"))
        }
        return AccountRecord(kind: provider.kind, address: address, refreshToken: refreshToken)
    }
}

// RemoteAccount keeps one signed-in account's access token fresh and reads its events.
public actor RemoteAccount: AccountSession {
    // provider is the service and app registration.
    public let provider: OAuthProvider
    // record is the stored account, updated when the service rotates the refresh token.
    public private(set) var record: AccountRecord

    // client sends HTTP requests.
    private let client: HTTPClient
    // clock returns the current time.
    private let clock: @Sendable () -> Date
    // onRecordChange persists a record whose refresh token changed.
    private let onRecordChange: @Sendable (AccountRecord) -> Void
    // access is the current access token and its expiry.
    private var access: (token: String, expiresAt: Date)?
    // refreshMargin renews an access token this many seconds before it expires.
    private let refreshMargin: TimeInterval = 60

    // init creates an account session with no access token yet.
    public init(
        provider: OAuthProvider,
        record: AccountRecord,
        client: HTTPClient,
        clock: @escaping @Sendable () -> Date = Date.init,
        onRecordChange: @escaping @Sendable (AccountRecord) -> Void
    ) {
        self.provider = provider
        self.record = record
        self.client = client
        self.clock = clock
        self.onRecordChange = onRecordChange
    }

    // entries reads events in the window, refreshing the access token once if the service rejects it.
    public func entries(from: Date, to: Date) async throws -> [CalendarEntry] {
        do {
            return try await fetch(accessToken: try await accessToken(), from: from, to: to)
        } catch RemoteError.unauthorized {
            access = nil
            return try await fetch(accessToken: try await accessToken(), from: from, to: to)
        }
    }

    // accessToken returns a token valid for at least the refresh margin, refreshing when needed.
    func accessToken() async throws -> String {
        let now = clock()
        if let access, access.expiresAt.timeIntervalSince(now) > refreshMargin {
            return access.token
        }
        guard let refreshToken = record.refreshToken else {
            throw AuthError.reauthorize("This account has no refresh token.")
        }
        let (data, status) = try await client.send(provider.refreshRequest(refreshToken: refreshToken))
        let tokens = try TokenSet.decode(data, status: status, now: now)
        access = (tokens.accessToken, tokens.expiresAt)
        if let rotated = tokens.refreshToken, !rotated.isEmpty, rotated != refreshToken {
            record.credential = .refreshToken(rotated)
            onRecordChange(record)
        }
        return tokens.accessToken
    }

    // fetch reads events with the given token from the account's service.
    private func fetch(accessToken: String, from: Date, to: Date) async throws -> [CalendarEntry] {
        switch provider.kind {
        case .microsoft:
            return try await GraphCalendar.fetch(
                client: client, accessToken: accessToken, from: from, to: to, selfAddress: record.address
            )
        case .google:
            return try await GoogleCalendar.fetch(client: client, accessToken: accessToken, from: from, to: to)
        case .icloud, .caldav, .exchange:
            throw AuthError.reauthorize("\(provider.kind.label) does not sign in through the browser.")
        }
    }
}

// PasswordSignIn checks a user name and password against a server before anything is saved.
public enum PasswordSignIn {
    // serverURL reads a typed server address, adding https when no scheme is given. It refuses anything but
    // https, except plain http to this Mac when allowLocalHTTP is set, which only debug builds do.
    public static func serverURL(_ text: String, allowLocalHTTP: Bool) -> URL? {
        var typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            return nil
        }
        if !typed.contains("://") {
            typed = "https://" + typed
        }
        guard let url = URL(string: typed), let host = url.host, !host.isEmpty else {
            return nil
        }
        switch url.scheme?.lowercased() {
        case "https":
            return url
        case "http" where allowLocalHTTP && ["localhost", "127.0.0.1"].contains(host.lowercased()):
            return url
        default:
            return nil
        }
    }

    // complete checks the credentials and returns the record to store and what CalDAV discovery found. An
    // Exchange server is checked by reading the next day of its calendar, through a client that answers the
    // server's challenge, and has no discovery.
    public static func complete(
        kind: AccountKind, server: URL, username: String, password: String, client: HTTPClient, now: Date = Date()
    ) async throws -> (AccountRecord, CalDAVCalendar.Discovery?) {
        if kind == .exchange {
            let endpoint = EWSCalendar.endpoint(server)
            _ = try await EWSCalendar.occurrences(
                client: client, server: endpoint, from: now, to: now.addingTimeInterval(24 * 60 * 60)
            )
            let record = AccountRecord(
                kind: kind, address: username,
                credential: .password(server: endpoint, username: username, password: password)
            )
            return (record, nil)
        }
        let discovery = try await CalDAVCalendar.discover(
            client: client, base: server, username: username, password: password
        )
        let record = AccountRecord(
            kind: kind, address: username, credential: .password(server: server, username: username, password: password)
        )
        return (record, discovery)
    }
}

// PasswordSession reads a password account's events, finding its calendar home once and again after a rejection.
public actor PasswordSession: AccountSession {
    // record is the stored account.
    public let record: AccountRecord

    // client sends HTTP requests.
    private let client: HTTPClient
    // discovery is the account's calendar home, found on first read or handed over by sign-in.
    private var discovery: CalDAVCalendar.Discovery?

    // init creates a session, reusing a discovery from sign-in when there is one.
    public init(record: AccountRecord, client: HTTPClient, discovery: CalDAVCalendar.Discovery? = nil) {
        self.record = record
        self.client = client
        self.discovery = discovery
    }

    // entries reads events in the window. A rejection rediscovers and retries once, and a second asks for sign-in.
    public func entries(from: Date, to: Date) async throws -> [CalendarEntry] {
        guard case .password(let server, let username, let password) = record.credential else {
            throw AuthError.reauthorize("This account has no password.")
        }
        do {
            return try await read(server: server, username: username, password: password, from: from, to: to)
        } catch RemoteError.unauthorized {
            discovery = nil
        }
        do {
            return try await read(server: server, username: username, password: password, from: from, to: to)
        } catch RemoteError.unauthorized {
            throw AuthError.reauthorize("The server no longer accepts the password.")
        }
    }

    // read discovers the home when needed and reads the window. Exchange reads over EWS and has no home.
    private func read(
        server: URL, username: String, password: String, from: Date, to: Date
    ) async throws -> [CalendarEntry] {
        if record.kind == .exchange {
            let addresses = username.contains("@") ? [username] : []
            return try await EWSCalendar.fetch(client: client, server: server, addresses: addresses, from: from, to: to)
        }
        let found: CalDAVCalendar.Discovery
        if let discovery {
            found = discovery
        } else {
            found = try await CalDAVCalendar.discover(
                client: client, base: server, username: username, password: password
            )
            discovery = found
        }
        return try await CalDAVCalendar.fetch(
            client: client, discovery: found, username: username, password: password, from: from, to: to
        )
    }
}
