import Foundation
import Testing

@testable import SheepdogCore

// testPKCEVector checks the S256 challenge against RFC 7636 appendix B.
@Test func testPKCEVector() {
    let got = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    #expect(got.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    #expect(got.method == "S256")
}

// testPKCEGenerate checks that generated verifiers are unpadded base64url of 32 bytes and never repeat.
@Test func testPKCEGenerate() {
    let first = PKCE.generate()
    let second = PKCE.generate()
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    #expect(first.verifier.count == 43)
    #expect(first.verifier.unicodeScalars.allSatisfy(allowed.contains))
    #expect(first.verifier != second.verifier)
    #expect(PKCE(verifier: first.verifier).challenge == first.challenge)
}

// AuthorizationURLCase is one authorization URL expectation.
struct AuthorizationURLCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Provider is the service under test.
    let provider: OAuthProvider
    // WantHost is the expected authorization host.
    let wantHost: String
    // WantRedirect is the expected redirect URI for port 51234.
    let wantRedirect: String
    // WantQuery is the expected query.
    let wantQuery: [String: String]

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// authorizationURLCases covers both providers.
let authorizationURLCases: [AuthorizationURLCase] = [
    AuthorizationURLCase( // Test 0: Microsoft uses localhost and asks for offline access.
        name: "microsoft",
        provider: .microsoft(clientID: "ms-client"),
        wantHost: "login.microsoftonline.com",
        wantRedirect: "http://localhost:51234",
        wantQuery: [
            "client_id": "ms-client",
            "response_type": "code",
            "redirect_uri": "http://localhost:51234",
            "scope": "offline_access User.Read Calendars.Read",
            "state": "st",
            "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            "code_challenge_method": "S256",
            "prompt": "select_account",
        ]
    ),
    AuthorizationURLCase( // Test 1: Google uses 127.0.0.1 and forces consent so a refresh token comes back.
        name: "google",
        provider: .google(clientID: "g-client", clientSecret: "g-secret"),
        wantHost: "accounts.google.com",
        wantRedirect: "http://127.0.0.1:51234",
        wantQuery: [
            "client_id": "g-client",
            "response_type": "code",
            "redirect_uri": "http://127.0.0.1:51234",
            "scope": "https://www.googleapis.com/auth/calendar.readonly",
            "state": "st",
            "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            "code_challenge_method": "S256",
            "access_type": "offline",
            "prompt": "consent",
        ]
    ),
]

// testAuthorizationURL checks the browser sign-in URL for each provider.
@Test(arguments: authorizationURLCases)
func testAuthorizationURL(test: AuthorizationURLCase) {
    let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    let redirect = test.provider.redirectURI(port: 51234)
    let got = test.provider.authorizationURL(pkce: pkce, state: "st", redirectURI: redirect)
    #expect(redirect == test.wantRedirect)
    #expect(got.host == test.wantHost)
    #expect(queryItems(got) == test.wantQuery)
    #expect(!got.absoluteString.contains("client_secret"))
}

// TokenRequestCase is one token endpoint request expectation.
struct TokenRequestCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Request is the request under test.
    let request: URLRequest
    // WantURL is the expected token endpoint.
    let wantURL: String
    // WantBody is the expected form body.
    let wantBody: String

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// tokenRequestCases covers code exchange and refresh for both providers.
let tokenRequestCases: [TokenRequestCase] = {
    let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    let microsoft = OAuthProvider.microsoft(clientID: "ms-client")
    let google = OAuthProvider.google(clientID: "g-client", clientSecret: "g-secret")
    return [
        TokenRequestCase( // Test 0: Microsoft code exchange has no secret and escapes the redirect.
            name: "microsoft code",
            request: microsoft.tokenRequest(code: "c/1+2", pkce: pkce, redirectURI: "http://localhost:5000"),
            wantURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            wantBody: "client_id=ms-client&grant_type=authorization_code&code=c%2F1%2B2"
                + "&redirect_uri=http%3A%2F%2Flocalhost%3A5000&code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        ),
        TokenRequestCase( // Test 1: Google code exchange sends the desktop client secret.
            name: "google code",
            request: google.tokenRequest(code: "c", pkce: pkce, redirectURI: "http://127.0.0.1:5000"),
            wantURL: "https://oauth2.googleapis.com/token",
            wantBody: "client_id=g-client&grant_type=authorization_code&code=c"
                + "&redirect_uri=http%3A%2F%2F127.0.0.1%3A5000&code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
                + "&client_secret=g-secret"
        ),
        TokenRequestCase( // Test 2: Microsoft refresh repeats the scopes.
            name: "microsoft refresh",
            request: microsoft.refreshRequest(refreshToken: "r"),
            wantURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            wantBody: "client_id=ms-client&grant_type=refresh_token&refresh_token=r"
                + "&scope=offline_access%20User.Read%20Calendars.Read"
        ),
        TokenRequestCase( // Test 3: Google refresh sends no scope.
            name: "google refresh",
            request: google.refreshRequest(refreshToken: "r"),
            wantURL: "https://oauth2.googleapis.com/token",
            wantBody: "client_id=g-client&grant_type=refresh_token&refresh_token=r&client_secret=g-secret"
        ),
        TokenRequestCase( // Test 4: An empty Google secret is left out.
            name: "google empty secret",
            request: OAuthProvider.google(clientID: "g-client", clientSecret: "").refreshRequest(refreshToken: "r"),
            wantURL: "https://oauth2.googleapis.com/token",
            wantBody: "client_id=g-client&grant_type=refresh_token&refresh_token=r"
        ),
    ]
}()

// testTokenRequest checks token endpoint requests.
@Test(arguments: tokenRequestCases)
func testTokenRequest(test: TokenRequestCase) {
    #expect(test.request.httpMethod == "POST")
    #expect(test.request.url?.absoluteString == test.wantURL)
    #expect(test.request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    #expect(bodyText(test.request) == test.wantBody)
}

// TokenDecodeCase is one token response expectation.
struct TokenDecodeCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Body is the response body.
    let body: Data
    // Status is the response status.
    let status: Int
    // WantResult is the expected token set, when decoding succeeds.
    let wantResult: TokenSet?
    // Want is the expected error, when decoding fails.
    let want: AuthError?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// tokenDecodeCases covers success, missing refresh token and each error class.
let tokenDecodeCases: [TokenDecodeCase] = {
    let now = utc("2026-10-22T15:00:00Z")
    return [
        TokenDecodeCase( // Test 0: Full response.
            name: "ok", body: fixture("token-ok.json"), status: 200,
            wantResult: TokenSet(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(3599)),
            want: nil
        ),
        TokenDecodeCase( // Test 1: A refresh without a new refresh token.
            name: "no refresh token", body: fixture("token-no-refresh.json"), status: 200,
            wantResult: TokenSet(accessToken: "access-2", refreshToken: nil, expiresAt: now.addingTimeInterval(3599)),
            want: nil
        ),
        TokenDecodeCase( // Test 2: A revoked or expired refresh token needs a new sign-in.
            name: "invalid grant", body: fixture("token-invalid-grant.json"), status: 400,
            wantResult: nil, want: .reauthorize("Token has been expired or revoked.")
        ),
        TokenDecodeCase( // Test 3: Other OAuth errors carry the status and code.
            name: "server", body: fixture("token-server.json"), status: 503,
            wantResult: nil, want: .server(status: 503, code: "temporarily_unavailable")
        ),
        TokenDecodeCase( // Test 4: A non-JSON error body still reports the status.
            name: "html error", body: Data("<html>".utf8), status: 502,
            wantResult: nil, want: .server(status: 502, code: nil)
        ),
        TokenDecodeCase( // Test 5: A success without an access token is malformed.
            name: "malformed", body: Data(#"{"token_type":"Bearer"}"#.utf8), status: 200,
            wantResult: nil, want: .decode
        ),
    ]
}()

// testTokenDecode checks token response decoding.
@Test(arguments: tokenDecodeCases)
func testTokenDecode(test: TokenDecodeCase) {
    let now = utc("2026-10-22T15:00:00Z")
    do {
        let got = try TokenSet.decode(test.body, status: test.status, now: now)
        #expect(test.want == nil)
        #expect(got == test.wantResult)
    } catch {
        #expect(error as? AuthError == test.want)
    }
}

// CallbackCase is one loopback redirect expectation.
struct CallbackCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Request is the raw HTTP request the browser sent.
    let request: String
    // WantTarget is the expected request target.
    let wantTarget: String?
    // WantCode is the expected authorization code.
    let wantCode: String?
    // Want is the expected error.
    let want: AuthError?
    // Kind is the service signing in.
    var kind: AccountKind = .google

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// callbackCases covers the redirect, unrelated requests, refusals and forged state.
let callbackCases: [CallbackCase] = [
    CallbackCase( // Test 0: The redirect carries a code and the right state.
        name: "code",
        request: "GET /?code=M.C5%2Fab&state=st HTTP/1.1\r\nHost: localhost:5000\r\n\r\n",
        wantTarget: "/?code=M.C5%2Fab&state=st", wantCode: "M.C5/ab", want: nil
    ),
    CallbackCase( // Test 1: Google adds scope and authuser.
        name: "google extras",
        request: "GET /?state=st&code=4/0Ab&scope=https://www.googleapis.com/auth/calendar.readonly&authuser=0 HTTP/1.1\r\n\r\n",
        wantTarget: "/?state=st&code=4/0Ab&scope=https://www.googleapis.com/auth/calendar.readonly&authuser=0",
        wantCode: "4/0Ab", want: nil
    ),
    CallbackCase( // Test 2: A favicon request is not the redirect.
        name: "favicon",
        request: "GET /favicon.ico HTTP/1.1\r\n\r\n",
        wantTarget: "/favicon.ico", wantCode: nil, want: nil
    ),
    CallbackCase( // Test 3: A bare root request is not the redirect.
        name: "bare root",
        request: "GET / HTTP/1.1\r\n\r\n",
        wantTarget: "/", wantCode: nil, want: nil
    ),
    CallbackCase( // Test 4: The user refused consent.
        name: "denied",
        request: "GET /?error=access_denied&error_description=The+user+said+no&state=st HTTP/1.1\r\n\r\n",
        wantTarget: "/?error=access_denied&error_description=The+user+said+no&state=st",
        wantCode: nil, want: .refused(.userDeclined)
    ),
    CallbackCase( // Test 5: A code with a forged state is rejected.
        name: "state mismatch",
        request: "GET /?code=c&state=other HTTP/1.1\r\n\r\n",
        wantTarget: "/?code=c&state=other", wantCode: nil, want: .stateMismatch
    ),
    CallbackCase( // Test 6: An error with a forged state is also a state mismatch.
        name: "error state mismatch",
        request: "GET /?error=access_denied HTTP/1.1\r\n\r\n",
        wantTarget: "/?error=access_denied", wantCode: nil, want: .stateMismatch
    ),
    CallbackCase( // Test 7: A POST is not a redirect.
        name: "post",
        request: "POST /?code=c&state=st HTTP/1.1\r\n\r\n",
        wantTarget: nil, wantCode: nil, want: nil
    ),
    CallbackCase( // Test 8: Garbage is not a request.
        name: "garbage",
        request: "hello",
        wantTarget: nil, wantCode: nil, want: nil
    ),
    CallbackCase( // Test 9: A Microsoft tenant that needs admin consent.
        name: "microsoft admin approval",
        request: "GET /?error=access_denied&error_description=AADSTS65001%3A+The+user+or+administrator"
            + "+has+not+consented.+Trace+ID%3A+abc&state=st HTTP/1.1\r\n\r\n",
        wantTarget: "/?error=access_denied&error_description=AADSTS65001%3A+The+user+or+administrator"
            + "+has+not+consented.+Trace+ID%3A+abc&state=st",
        wantCode: nil, want: .refused(.adminApproval), kind: .microsoft
    ),
    CallbackCase( // Test 10: A redirect with an empty code is refused without a sentence from the URL.
        name: "empty code",
        request: "GET /?code=&state=st HTTP/1.1\r\n\r\n",
        wantTarget: "/?code=&state=st", wantCode: nil, want: .refused(.other(code: "no_code"))
    ),
]

// testCallback checks request line parsing and code extraction.
@Test(arguments: callbackCases)
func testCallback(test: CallbackCase) {
    let target = AuthorizationCallback.target(fromRequest: Data(test.request.utf8))
    #expect(target == test.wantTarget)
    guard let target else {
        return
    }
    do {
        let got = try AuthorizationCallback.code(fromTarget: target, expectedState: "st", kind: test.kind)
        #expect(test.want == nil)
        #expect(got == test.wantCode)
    } catch {
        #expect(error as? AuthError == test.want)
    }
}
