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
    SignInCase( // Test 0: Microsoft looks up the address in Graph.
        name: "microsoft",
        provider: .microsoft(clientID: "ms"),
        tokenReply: .ok("token-ok.json"),
        wantResult: AccountRecord(kind: .microsoft, address: "me@example.com", refreshToken: "refresh-1"),
        want: nil
    ),
    SignInCase( // Test 1: Google uses the primary calendar id.
        name: "google",
        provider: .google(clientID: "g", clientSecret: "s"),
        tokenReply: .ok("token-ok.json"),
        wantResult: AccountRecord(kind: .google, address: "me@example.com", refreshToken: "refresh-1"),
        want: nil
    ),
    SignInCase( // Test 2: No refresh token means the account could not stay signed in.
        name: "no refresh token",
        provider: .google(clientID: "g", clientSecret: "s"),
        tokenReply: .ok("token-no-refresh.json"),
        wantResult: nil,
        want: .noRefreshToken
    ),
    SignInCase( // Test 3: A refused code.
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
        if request.url?.host == "graph.microsoft.com" {
            return .ok("graph-me.json")
        }
        return .ok("google-primary.json")
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
