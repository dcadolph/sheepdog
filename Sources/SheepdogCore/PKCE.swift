import CryptoKit
import Foundation

// PKCE is the proof key for one authorization request, as defined by RFC 7636.
public struct PKCE: Sendable, Equatable {
    // Verifier is the secret sent with the token request.
    public let verifier: String
    // Challenge is the S256 hash of the verifier, sent with the authorization request.
    public let challenge: String
    // Method is the challenge method. Only S256 is used.
    public let method = "S256"

    // init derives the challenge from a verifier.
    public init(verifier: String) {
        self.verifier = verifier
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    // generate returns a proof key with a fresh 256-bit verifier.
    public static func generate() -> PKCE {
        PKCE(verifier: randomToken(bytes: 32))
    }

    // randomToken returns cryptographically random bytes encoded as base64url.
    public static func randomToken(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64URLEncoded
    }
}

extension Data {
    // base64URLEncoded is the unpadded base64url encoding from RFC 4648.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
