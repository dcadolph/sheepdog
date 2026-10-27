import Foundation
import Testing

@testable import SheepdogCore

// RecordBox collects the records an account asks to persist.
final class RecordBox: @unchecked Sendable {
    // lock guards saved.
    private let lock = NSLock()
    // saved holds every persisted record in order.
    private var saved: [AccountRecord] = []

    // save appends a record.
    func save(_ record: AccountRecord) {
        lock.withLock { saved.append(record) }
    }

    // records returns every persisted record.
    var records: [AccountRecord] {
        lock.withLock { saved }
    }
}

// isTokenRequest reports whether a request went to a token endpoint.
func isTokenRequest(_ request: URLRequest) -> Bool {
    request.url?.path.hasSuffix("/token") == true
}

// testRemoteAccountRefreshes checks that the first read refreshes, persists a rotated token and reuses the access token.
@Test func testRemoteAccountRefreshes() async throws {
    let clock = TestClock(utc("2026-10-22T15:00:00Z"))
    let box = RecordBox()
    let client = MockClient { request, _ in
        isTokenRequest(request) ? .ok("token-ok.json") : .ok("graph-page2.json")
    }
    let account = RemoteAccount(
        provider: .microsoft(clientID: "ms-client"),
        record: AccountRecord(kind: .microsoft, address: "me@example.com", refreshToken: "refresh-0"),
        client: client,
        clock: { clock.now() },
        onRecordChange: { box.save($0) }
    )
    let got = try await account.entries(from: Date(), to: Date())
    #expect(got.map(\.eventID) == ["graph:AAMkFocus", "graph:AAMkMaybe"])
    #expect(box.records == [AccountRecord(kind: .microsoft, address: "me@example.com", refreshToken: "refresh-1")])
    #expect(bodyText(client.requests[0]).contains("refresh_token=refresh-0"))
    #expect(client.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer access-1")

    // Test 1: Within the token's life no refresh happens.
    clock.advance(3000)
    _ = try await account.entries(from: Date(), to: Date())
    #expect(client.requests.filter(isTokenRequest).count == 1)

    // Test 2: Inside the refresh margin the token is renewed with the rotated refresh token.
    clock.advance(560)
    _ = try await account.entries(from: Date(), to: Date())
    let tokenRequests = client.requests.filter(isTokenRequest)
    #expect(tokenRequests.count == 2)
    #expect(bodyText(tokenRequests[1]).contains("refresh_token=refresh-1"))
    #expect(box.records.count == 1)
}

// testRemoteAccountRetriesUnauthorized checks that a rejected access token is refreshed and the read retried once.
@Test func testRemoteAccountRetriesUnauthorized() async throws {
    let client = MockClient { request, count in
        if isTokenRequest(request) {
            return .ok("token-ok.json")
        }
        return count == 1 ? .json("{}", status: 401) : .ok("graph-page2.json")
    }
    let account = RemoteAccount(
        provider: .microsoft(clientID: "ms-client"),
        record: AccountRecord(kind: .microsoft, address: nil, refreshToken: "refresh-1"),
        client: client,
        onRecordChange: { _ in }
    )
    let got = try await account.entries(from: Date(), to: Date())
    #expect(got.count == 2)
    #expect(client.requests.filter(isTokenRequest).count == 2)
    #expect(client.requests.count == 4)
}

// testRemoteAccountStillUnauthorized checks that a second rejection is reported rather than retried forever.
@Test func testRemoteAccountStillUnauthorized() async {
    let client = MockClient { request, _ in
        isTokenRequest(request) ? .ok("token-ok.json") : .json("{}", status: 401)
    }
    let account = RemoteAccount(
        provider: .google(clientID: "g", clientSecret: "s"),
        record: AccountRecord(kind: .google, address: nil, refreshToken: "refresh-1"),
        client: client,
        onRecordChange: { _ in }
    )
    await #expect(throws: RemoteError.unauthorized) {
        _ = try await account.entries(from: Date(), to: Date())
    }
    #expect(client.requests.count == 4)
}

// testRemoteAccountRevoked checks that a revoked refresh token asks for a new sign-in.
@Test func testRemoteAccountRevoked() async {
    let client = MockClient { _, _ in MockResponse(body: fixture("token-invalid-grant.json"), status: 400) }
    let account = RemoteAccount(
        provider: .google(clientID: "g", clientSecret: "s"),
        record: AccountRecord(kind: .google, address: "me@example.com", refreshToken: "old"),
        client: client,
        onRecordChange: { _ in }
    )
    await #expect(throws: AuthError.reauthorize("Token has been expired or revoked.")) {
        _ = try await account.entries(from: Date(), to: Date())
    }
}

// testRemoteAccountKeepsToken checks that a refresh with no new refresh token keeps the stored one.
@Test func testRemoteAccountKeepsToken() async throws {
    let box = RecordBox()
    let client = MockClient { request, _ in
        if isTokenRequest(request) {
            return .ok("token-no-refresh.json")
        }
        if request.url?.absoluteString.contains("calendarList") == true {
            return .json(#"{"items": [{"id": "me@example.com", "primary": true}]}"#)
        }
        return .json(#"{"items": []}"#)
    }
    let account = RemoteAccount(
        provider: .google(clientID: "g", clientSecret: "s"),
        record: AccountRecord(kind: .google, address: "me@example.com", refreshToken: "keep"),
        client: client,
        onRecordChange: { box.save($0) }
    )
    _ = try await account.entries(from: Date(), to: Date())
    #expect(box.records.isEmpty)
    #expect(await account.record.refreshToken == "keep")
}

// SignInCase is one sign-in completion expectation.
struct SignInCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Provider is the service.
    let provider: OAuthProvider
    // TokenReply is the token endpoint's reply.
    let tokenReply: MockResponse
    // WantResult is the expected record.
    let wantResult: AccountRecord?
    // Want is the expected error.
    let want: AuthError?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// signInCases covers both providers, a missing refresh token and a refused code.
let signInCases: [SignInCase] = [
    SignInCase( // Test 0: Microsoft reads the address from the email claim.
        name: "microsoft email",
        provider: .microsoft(clientID: "ms"),
        tokenReply: .ok("token-id-email.json"),
        wantResult: AccountRecord(kind: .microsoft, address: "me@example.com", refreshToken: "refresh-1"),
        want: nil
    ),
    SignInCase( // Test 1: Microsoft falls back to preferred_username.
        name: "microsoft username",
        provider: .microsoft(clientID: "ms"),
        tokenReply: .ok("token-id-upn.json"),
        wantResult: AccountRecord(
            kind: .microsoft, address: "upn@example.com", refreshToken: "refresh-1"
        ),
        want: nil
    ),
    SignInCase( // Test 2: Microsoft with neither claim still connects.
        name: "microsoft no address",
        provider: .microsoft(clientID: "ms"),
        tokenReply: .ok("token-id-none.json"),
        wantResult: AccountRecord(kind: .microsoft, address: nil, refreshToken: "refresh-1"),
        want: nil
    ),
    SignInCase( // Test 3: Google uses the primary calendar id.
        name: "google",
        provider: .google(clientID: "g", clientSecret: "s"),
        tokenReply: .ok("token-ok.json"),
        wantResult: AccountRecord(kind: .google, address: "me@example.com", refreshToken: "refresh-1"),
        want: nil
    ),
    SignInCase( // Test 4: No refresh token means the account could not stay signed in.
        name: "no refresh token",
        provider: .google(clientID: "g", clientSecret: "s"),
        tokenReply: .ok("token-no-refresh.json"),
        wantResult: nil,
        want: .noRefreshToken
    ),
    SignInCase( // Test 5: A refused code.
        name: "refused",
        provider: .microsoft(clientID: "ms"),
        tokenReply: MockResponse(body: fixture("token-invalid-grant.json"), status: 400),
        wantResult: nil,
        want: .reauthorize("Token has been expired or revoked.")
    ),
]

// testSignInComplete checks code exchange and address lookup.
@Test(arguments: signInCases)
func testSignInComplete(test: SignInCase) async {
    let tokenReply = test.tokenReply
    let client = MockClient { request, _ in
        if isTokenRequest(request) {
            return tokenReply
        }
        return .ok("google-calendars.json")
    }
    do {
        let got = try await SignIn.complete(
            provider: test.provider,
            code: "c",
            pkce: PKCE.generate(),
            redirectURI: test.provider.redirectURI(port: 5000),
            client: client,
            now: Date()
        )
        #expect(test.want == nil)
        #expect(got == test.wantResult)
    } catch {
        #expect(error as? AuthError == test.want)
    }
}

// testAccountRecordRedacts checks that printing a record never shows the refresh token.
@Test func testAccountRecordRedacts() {
    let record = AccountRecord(kind: .google, address: "me@example.com", refreshToken: "1//secret-token")
    for text in [String(describing: record), "\(record)", String(reflecting: [record])] {
        #expect(!text.contains("secret-token"), "\(text)")
        #expect(text.contains("<redacted>"))
    }
}

// testAccountRecordRedactsPassword checks that printing a password record never shows the password.
@Test func testAccountRecordRedactsPassword() {
    let record = AccountRecord(
        kind: .icloud, address: "me@icloud.com",
        credential: .password(server: CalDAVCalendar.iCloudURL, username: "me@icloud.com", password: "abcd-efgh-ijkl")
    )
    let texts = [String(describing: record), "\(record)", String(reflecting: [record]), "\(record.credential)"]
    for text in texts {
        #expect(!text.contains("abcd-efgh-ijkl"), "\(text)")
        #expect(text.contains("<redacted>"))
    }
}

// testAccountRecordCoding checks the Keychain payload: a stored browser sign-in keeps decoding, and a
// password record round-trips.
@Test func testAccountRecordCoding() throws {
    let stored = Data(#"{"kind":"microsoft","address":"me@example.com","refreshToken":"r-1"}"#.utf8)
    let decoded = try JSONDecoder().decode(AccountRecord.self, from: stored)
    #expect(decoded == AccountRecord(kind: .microsoft, address: "me@example.com", refreshToken: "r-1"))
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: String]
    #expect(encoded == ["kind": "microsoft", "address": "me@example.com", "refreshToken": "r-1"])

    let record = AccountRecord(
        kind: .icloud, address: "me@icloud.com",
        credential: .password(server: CalDAVCalendar.iCloudURL, username: "me@icloud.com", password: "pw")
    )
    #expect(try JSONDecoder().decode(AccountRecord.self, from: JSONEncoder().encode(record)) == record)
}

// testSettingsCarryNoCredentials checks that settings, which live in UserDefaults and in exports, have no
// field that could hold a sign-in.
@Test func testSettingsCarryNoCredentials() throws {
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AlertSettings())) as? [String: Any]
    let keys = Set(json?.keys.map { $0.lowercased() } ?? [])
    #expect(!keys.isEmpty)
    #expect(keys.isDisjoint(with: ["password", "refreshtoken", "username", "credential", "server"]))
}

// testPasswordSignIn checks that sign-in runs discovery and builds the record to store.
@Test func testPasswordSignIn() async throws {
    let (record, discovery) = try await PasswordSignIn.complete(
        kind: .icloud, server: caldavRoot, username: "Me@iCloud.com", password: "pw", client: caldavClient()
    )
    #expect(record == AccountRecord(
        kind: .icloud, address: "Me@iCloud.com",
        credential: .password(server: caldavRoot, username: "Me@iCloud.com", password: "pw")
    ))
    #expect(discovery == caldavDiscovery)
}

// testPasswordSignInRefused checks that a wrong password fails sign-in so nothing is saved.
@Test func testPasswordSignInRefused() async {
    let client = MockClient { _, _ in .json("", status: 401) }
    await #expect(throws: RemoteError.unauthorized) {
        _ = try await PasswordSignIn.complete(
            kind: .icloud, server: caldavRoot, username: "me@icloud.com", password: "bad", client: client
        )
    }
}

// icloudRecord is a stored iCloud sign-in for session tests.
let icloudRecord = AccountRecord(
    kind: .icloud, address: "me@icloud.com",
    credential: .password(server: caldavRoot, username: "me@icloud.com", password: "pw")
)

// testPasswordSessionReads checks that a session discovers once and reuses the home on the next read.
@Test func testPasswordSessionReads() async throws {
    let client = caldavClient()
    let session = PasswordSession(record: icloudRecord, client: client)
    let from = utc("2026-10-22T14:00:00Z"), to = utc("2026-10-23T02:00:00Z")
    #expect(try await session.entries(from: from, to: to).count == 4)
    let first = client.requests.count
    #expect(try await session.entries(from: from, to: to).count == 4)
    #expect(first == 5)
    #expect(client.requests.count - first == 3)
}

// testPasswordSessionRetriesOnce checks that one rejection rediscovers and reads again.
@Test func testPasswordSessionRetriesOnce() async throws {
    let inner = caldavClient()
    let client = MockClient { request, count in
        count == 0 ? .json("", status: 401) : inner.reply(request)
    }
    let session = PasswordSession(record: icloudRecord, client: client, discovery: caldavDiscovery)
    let got = try await session.entries(from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z"))
    #expect(got.count == 4)
    #expect(client.requests.filter { $0.value(forHTTPHeaderField: "Depth") == "0" }.count == 2)
}

// testPasswordSessionNeedsSignIn checks that a second rejection asks for sign-in instead of retrying again.
@Test func testPasswordSessionNeedsSignIn() async {
    let client = MockClient { _, _ in .json("", status: 401) }
    let session = PasswordSession(record: icloudRecord, client: client, discovery: caldavDiscovery)
    await #expect(throws: AuthError.reauthorize("The server no longer accepts the password.")) {
        _ = try await session.entries(from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z"))
    }
    #expect(client.requests.count == 2)
}

// ServerURLCase is one typed server address and what sign-in makes of it.
struct ServerURLCase: Sendable, CustomTestStringConvertible {
    // Typed is what the user typed.
    let typed: String
    // AllowLocalHTTP is set only in debug builds.
    let allowLocalHTTP: Bool
    // WantResult is the address sign-in uses, or nil when it refuses.
    let wantResult: String?

    // testDescription labels the case in test output.
    var testDescription: String { "\(typed) local=\(allowLocalHTTP)" }
}

// serverURLCases covers https, a bare host, plain http and the debug exception for this Mac.
let serverURLCases: [ServerURLCase] = [
    ServerURLCase( // Test 0: https as typed.
        typed: "https://caldav.fastmail.com/dav/", allowLocalHTTP: false, wantResult: "https://caldav.fastmail.com/dav/"
    ),
    ServerURLCase( // Test 1: A bare host gets https.
        typed: " cloud.example.org/remote.php/dav ", allowLocalHTTP: false,
        wantResult: "https://cloud.example.org/remote.php/dav"
    ),
    ServerURLCase( // Test 2: Plain http to another host is refused, even in debug.
        typed: "http://caldav.example.com/", allowLocalHTTP: true, wantResult: nil
    ),
    ServerURLCase( // Test 3: Release builds refuse plain http to this Mac.
        typed: "http://localhost:5232/", allowLocalHTTP: false, wantResult: nil
    ),
    ServerURLCase( // Test 4: Debug builds allow plain http to localhost.
        typed: "http://localhost:5232/", allowLocalHTTP: true, wantResult: "http://localhost:5232/"
    ),
    ServerURLCase( // Test 5: Debug builds allow plain http to the loopback address.
        typed: "http://127.0.0.1:5232/", allowLocalHTTP: true, wantResult: "http://127.0.0.1:5232/"
    ),
    ServerURLCase( // Test 6: Release builds refuse the loopback address too.
        typed: "http://127.0.0.1:5232/", allowLocalHTTP: false, wantResult: nil
    ),
    ServerURLCase( // Test 7: Empty.
        typed: "  ", allowLocalHTTP: true, wantResult: nil
    ),
    ServerURLCase( // Test 8: Another scheme.
        typed: "ftp://caldav.example.com/", allowLocalHTTP: true, wantResult: nil
    ),
]

// testPasswordServerURL checks which typed server addresses sign-in accepts.
@Test(arguments: serverURLCases)
func testPasswordServerURL(test: ServerURLCase) {
    let got = PasswordSignIn.serverURL(test.typed, allowLocalHTTP: test.allowLocalHTTP)
    #expect(got?.absoluteString == test.wantResult)
}

// testAccountKindOrder checks the order that drives the Calendars tab and entry precedence.
@Test func testAccountKindOrder() {
    #expect(AccountKind.allCases == [.microsoft, .google, .icloud, .caldav])
    #expect(AccountKind.allCases.filter(\.usesPassword) == [.icloud, .caldav])
    #expect(AccountKind.caldav.server == nil)
    #expect(AccountKind.icloud.server == CalDAVCalendar.iCloudURL)
}
