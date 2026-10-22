import Foundation

// KeychainError is a failed Keychain call, carrying the Security framework status.
struct KeychainError: Error, Equatable {
    // Status is the OSStatus the call returned.
    let status: OSStatus
}

// LoopbackError is a failure of the local sign-in redirect listener.
enum LoopbackError: Error, Equatable {
    // timeout means the browser did not return within the sign-in window.
    case timeout
    // canceled means the sign-in was abandoned.
    case canceled
    // noPort means the listener became ready without a port.
    case noPort
}
