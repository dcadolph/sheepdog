import Foundation

// AccountRecord is what Sheepdog stores in the Keychain for one signed-in account.
public struct AccountRecord: Sendable, Codable, Equatable, CustomStringConvertible {
    // Kind is the service.
    public var kind: AccountKind
    // Address is the account's mail address, shown in settings.
    public var address: String?
    // RefreshToken keeps the account signed in. It is secret and only ever written to the Keychain.
    public var refreshToken: String

    // init creates a record.
    public init(kind: AccountKind, address: String?, refreshToken: String) {
        self.kind = kind
        self.address = address
        self.refreshToken = refreshToken
    }

    // description identifies the account with the refresh token redacted, so logging a record never leaks it.
    public var description: String {
        "AccountRecord(kind: \(kind.rawValue), address: \(address ?? "nil"), refreshToken: <redacted>)"
    }
}

// SignIn finishes a browser sign-in once the redirect has delivered a code.
public enum SignIn {
    // complete exchanges the code for tokens and looks up the account's address.
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
            address = try await GraphCalendar.profile(client: client, accessToken: tokens.accessToken)
        case .google:
            address = try await GoogleCalendar.profile(client: client, accessToken: tokens.accessToken)
        }
        return AccountRecord(kind: provider.kind, address: address, refreshToken: refreshToken)
    }
}

// RemoteAccount keeps one signed-in account's access token fresh and reads its events.
public actor RemoteAccount {
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
        let (data, status) = try await client.send(provider.refreshRequest(refreshToken: record.refreshToken))
        let tokens = try TokenSet.decode(data, status: status, now: now)
        access = (tokens.accessToken, tokens.expiresAt)
        if let rotated = tokens.refreshToken, !rotated.isEmpty, rotated != record.refreshToken {
            record.refreshToken = rotated
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
        }
    }
}
