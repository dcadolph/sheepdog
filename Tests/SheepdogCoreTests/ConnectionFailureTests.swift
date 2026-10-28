import Foundation
import Testing

@testable import SheepdogCore

// FailureCase is one URL loading error and the failure it should sort into.
struct FailureCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Code is the URL loading error code.
    let code: URLError.Code
    // Want is the expected failure.
    let want: ConnectionFailure

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// failureCases covers every secure code the classifier names plus common unreachable ones.
let failureCases: [FailureCase] = [
    FailureCase( // Test 0: The handshake failed, as ATS -9802 behind TLS inspection reports it.
        name: "secureConnectionFailed", code: .secureConnectionFailed, want: .secureConnection
    ),
    FailureCase( // Test 1: The server certificate expired.
        name: "serverCertificateHasBadDate", code: .serverCertificateHasBadDate, want: .secureConnection
    ),
    FailureCase( // Test 2: The server certificate is signed by an untrusted root.
        name: "serverCertificateUntrusted", code: .serverCertificateUntrusted, want: .secureConnection
    ),
    FailureCase( // Test 3: The server certificate's root is unknown.
        name: "serverCertificateHasUnknownRoot", code: .serverCertificateHasUnknownRoot,
        want: .secureConnection
    ),
    FailureCase( // Test 4: The server certificate is not valid yet.
        name: "serverCertificateNotYetValid", code: .serverCertificateNotYetValid, want: .secureConnection
    ),
    FailureCase( // Test 5: The server rejected the client certificate.
        name: "clientCertificateRejected", code: .clientCertificateRejected, want: .secureConnection
    ),
    FailureCase( // Test 6: The server asked for a client certificate.
        name: "clientCertificateRequired", code: .clientCertificateRequired, want: .secureConnection
    ),
    FailureCase( // Test 7: The Mac is offline.
        name: "notConnectedToInternet", code: .notConnectedToInternet, want: .unreachable
    ),
    FailureCase( // Test 8: The request timed out.
        name: "timedOut", code: .timedOut, want: .unreachable
    ),
    FailureCase( // Test 9: The host name did not resolve.
        name: "cannotFindHost", code: .cannotFindHost, want: .unreachable
    ),
]

// testConnectionFailureClassify checks each code sorts into its case, including when it arrives as
// an NSError in NSURLErrorDomain.
@Test(arguments: failureCases)
func testConnectionFailureClassify(test: FailureCase) {
    #expect(ConnectionFailure.classify(URLError(test.code)) == test.want)
    let bridged = NSError(domain: NSURLErrorDomain, code: test.code.rawValue) as Error
    #expect((bridged as? URLError).map(ConnectionFailure.classify) == test.want)
}

// testConnectionFailureMessage checks the secure case names a next step and the unreachable case
// keeps its sentence.
@Test func testConnectionFailureMessage() {
    #expect(ConnectionFailure.secureConnection.message.contains("secure connection"))
    #expect(ConnectionFailure.secureConnection.message.contains("Internet Accounts"))
    #expect(ConnectionFailure.unreachable.message == "Couldn't reach the calendar service.")
}
