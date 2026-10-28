import Foundation

// ConnectionFailure is why a request never got an answer from a calendar service, sorted by what the
// user can do next.
public enum ConnectionFailure: Sendable, Equatable {
    // secureConnection means the secure connection failed, as it does when security software on the
    // network inspects encrypted traffic or the server's certificate is not trusted.
    case secureConnection
    // unreachable is any other failure to reach the service.
    case unreachable

    // secureCodes are the URL loading codes for a failed handshake or certificate.
    private static let secureCodes: Set<URLError.Code> = [
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot,
        .serverCertificateNotYetValid,
        .clientCertificateRejected,
        .clientCertificateRequired,
    ]

    // classify sorts a URL loading error into a failure.
    public static func classify(_ error: URLError) -> ConnectionFailure {
        secureCodes.contains(error.code) ? .secureConnection : .unreachable
    }

    // message tells the user what happened and what to do next.
    public var message: String {
        switch self {
        case .secureConnection:
            return "Sheepdog couldn't make a secure connection to the calendar service. Security "
                + "software on a work network often causes this. Try another network, or add the "
                + "account in System Settings, Internet Accounts, and Sheepdog reads it through "
                + "macOS Calendar."
        case .unreachable:
            return "Couldn't reach the calendar service."
        }
    }
}
