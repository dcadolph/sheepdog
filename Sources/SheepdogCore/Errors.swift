import Foundation

// AuthError is a failure to sign in or to keep an account signed in.
public enum AuthError: Error, Sendable, Equatable {
    // stateMismatch means the redirect carried a state that this sign-in did not send.
    case stateMismatch
    // denied means the user or the provider refused the request, with the provider's reason.
    case denied(String)
    // noRefreshToken means the token response had no refresh token, so the account cannot stay signed in.
    case noRefreshToken
    // reauthorize means the refresh token is no longer accepted and the user must sign in again.
    case reauthorize(String)
    // server means the token endpoint returned an error the app cannot act on.
    case server(status: Int, code: String?)
    // decode means a response body was not the expected JSON.
    case decode
}

// RemoteError is a failure to read events from a calendar service.
public enum RemoteError: Error, Sendable, Equatable {
    // unauthorized means the access token was rejected.
    case unauthorized
    // server means the service returned a status other than success or unauthorized.
    case server(status: Int)
    // decode means a response body was not the expected JSON.
    case decode
    // tooManyPages means paging did not end within the page limit.
    case tooManyPages
}
