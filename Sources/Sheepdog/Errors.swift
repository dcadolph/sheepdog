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

// UpdaterError is a failure to install an update from the update card.
enum UpdaterError: Error, Equatable {
    // noBrew means Homebrew manages Sheepdog but its executable was not found.
    case noBrew
    // brew means the Homebrew upgrade failed, carrying the script's exit status.
    case brew(status: Int32)
    // download means the release's disk image did not download, carrying the HTTP status.
    case download(status: Int)
    // attach means the disk image could not be mounted.
    case attach
    // signature means the app on the disk image is not signed by the release team.
    case signature
    // version means the app on the disk image is not the version the card named.
    case version
}
