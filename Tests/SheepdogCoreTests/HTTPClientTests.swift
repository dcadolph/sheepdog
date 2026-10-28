import Foundation
import Testing

@testable import SheepdogCore

// FailingProtocol fails every request with the URLError code named in the request's X-Fail header.
final class FailingProtocol: URLProtocol, @unchecked Sendable {
    // canInit takes every request.
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // canonicalRequest returns the request unchanged.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // startLoading fails the request with the code from its header.
    override func startLoading() {
        let raw = Int(request.value(forHTTPHeaderField: "X-Fail") ?? "") ?? URLError.Code.unknown.rawValue
        client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: raw)))
    }

    // stopLoading has nothing to stop.
    override func stopLoading() {}
}

// SendErrorCase is one transport failure and the error send should throw for it.
struct SendErrorCase: Sendable, CustomTestStringConvertible {
    // name labels the case.
    let name: String
    // code is the URLError the transport fails with.
    let code: URLError.Code
    // wantUnauthorized reports whether send should throw RemoteError.unauthorized.
    let wantUnauthorized: Bool

    // testDescription names the case in test output.
    var testDescription: String { name }
}

// sendErrorCases covers the canceled authentication iCloud produces and failures that must pass through.
let sendErrorCases: [SendErrorCase] = [
    SendErrorCase( // Test 0: CFNetwork canceled the authentication after the server refused the password.
        name: "canceled auth", code: .userCancelledAuthentication, wantUnauthorized: true
    ),
    SendErrorCase( // Test 1: No network stays a network error.
        name: "offline", code: .notConnectedToInternet, wantUnauthorized: false
    ),
    SendErrorCase( // Test 2: A canceled task is not a refused password.
        name: "canceled", code: .cancelled, wantUnauthorized: false
    ),
]

// testURLSessionClientSendErrors checks that only a canceled authentication becomes unauthorized.
@Test(arguments: sendErrorCases)
func testURLSessionClientSendErrors(test: SendErrorCase) async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FailingProtocol.self]
    let client = URLSessionClient(session: URLSession(configuration: configuration))
    var request = URLRequest(url: URL(string: "https://caldav.icloud.com/")!)
    request.setValue(String(test.code.rawValue), forHTTPHeaderField: "X-Fail")
    do {
        _ = try await client.send(request)
        Issue.record("send succeeded")
    } catch let error as RemoteError {
        #expect(test.wantUnauthorized)
        #expect(error == .unauthorized)
    } catch let error as URLError {
        #expect(!test.wantUnauthorized)
        #expect(error.code == test.code)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
