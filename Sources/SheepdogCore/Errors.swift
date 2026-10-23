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

// BackupError is a failure to read a settings backup file.
public enum BackupError: Error, Sendable, Equatable {
    // unreadable means the file is not a settings backup in any form this app understands.
    case unreadable
    // notSheepdog means the file is a backup from another app.
    case notSheepdog(String)
    // newerVersion means the file was written by a newer Sheepdog, with the file's version.
    case newerVersion(Int)
}

// UpdateError is a failure to learn whether a newer release exists.
public enum UpdateError: Error, Sendable, Equatable {
    // server means GitHub returned a status other than success, e.g. a rate limit.
    case server(status: Int)
    // decode means the response body was not a release.
    case decode
}
