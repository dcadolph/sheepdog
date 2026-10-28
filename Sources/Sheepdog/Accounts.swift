import AppKit
import Foundation
import Observation
import os

import SheepdogCore

// AccountState is what settings shows for one service.
enum AccountState: Equatable {
    // notConfigured means this build has no client id for the service.
    case notConfigured
    // signedOut means no account is connected.
    case signedOut
    // signingIn means the browser sign-in or the password check is in progress.
    case signingIn
    // connected means events are being read, from the account with this address when known.
    case connected(String?)
    // needsSignIn means the service stopped accepting the stored sign-in.
    case needsSignIn(String?)
}

// Accounts owns the calendar sign-ins and the events last read from them.
@MainActor
@Observable
final class Accounts {
    // states is the settings view of each service.
    private(set) var states: [AccountKind: AccountState] = [:]
    // problems holds the last sign-in or read failure per service, for display.
    private(set) var problems: [AccountKind: String] = [:]
    // refusals holds why the last browser sign-in was refused per service, so settings can offer
    // the next step.
    private(set) var refusals: [AccountKind: SignInRefusal] = [:]
    // passwordPrompt is the password service whose sign-in sheet is showing.
    var passwordPrompt: AccountKind?
    // onChange is called when the cached events or the account list change.
    @ObservationIgnored var onChange: (() -> Void)?

    // providers are the services this build has client ids for.
    @ObservationIgnored private var providers: [AccountKind: OAuthProvider] = [:]
    // sessions are the connected accounts.
    @ObservationIgnored private var sessions: [AccountKind: any AccountSession] = [:]
    // cache holds the events last read per service. It is kept through failures so a lapsed
    // sign-in never silences meetings that were already known.
    @ObservationIgnored private var cache: [AccountKind: [CalendarEntry]] = [:]
    // pending is the loopback listener of a sign-in in progress.
    @ObservationIgnored private var pending: [AccountKind: LoopbackServer] = [:]
    // lastRead is when the services were last read.
    @ObservationIgnored private var lastRead = Date.distantPast
    // reading reports a read in progress.
    @ObservationIgnored private var reading = false
    // client sends API requests.
    @ObservationIgnored private let client = URLSessionClient()
    // interval is how often the services are read.
    private let interval: TimeInterval = 120
    // lookahead is how far ahead events are read.
    private let lookahead: TimeInterval = 12 * 3600
    // log records failures without tokens or event content.
    @ObservationIgnored private let log = Logger(subsystem: "com.dcadolph.sheepdog", category: "accounts")

    // init reads client ids from the bundle and restores stored accounts.
    init(bundle: Bundle = .main) {
        let value = { (key: String) -> String? in
            let text = (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
            return text?.isEmpty == false ? text : nil
        }
        if let id = value("SheepdogMicrosoftClientID") {
            providers[.microsoft] = .microsoft(clientID: id)
        }
        if let id = value("SheepdogGoogleClientID") {
            providers[.google] = .google(clientID: id, clientSecret: value("SheepdogGoogleClientSecret"))
        }
        for kind in AccountKind.allCases {
            guard kind.usesPassword || providers[kind] != nil else {
                states[kind] = .notConfigured
                continue
            }
            if let record = Keychain.load(kind) {
                attach(record)
            } else {
                states[kind] = .signedOut
            }
        }
    }

    // init shows the given states without reading the Keychain, for offscreen renders.
    init(fixture: [AccountKind: AccountState]) {
        states = fixture
    }

    // entries returns the cached events of every connected service, Microsoft first.
    var entries: [[CalendarEntry]] {
        AccountKind.allCases.compactMap { cache[$0] }
    }

    // hasAccounts reports whether any service is connected.
    var hasAccounts: Bool {
        !sessions.isEmpty
    }

    // connect runs the browser sign-in for a service, or shows the sign-in sheet for a password service.
    func connect(_ kind: AccountKind) {
        if kind.usesPassword {
            problems[kind] = nil
            passwordPrompt = kind
            return
        }
        guard let provider = providers[kind], states[kind] != .signingIn else {
            return
        }
        let previous = states[kind] ?? .signedOut
        states[kind] = .signingIn
        problems[kind] = nil
        refusals[kind] = nil
        Task {
            do {
                let record = try await signIn(provider)
                try Keychain.save(record)
                attach(record)
                refresh(force: true)
            } catch LoopbackError.canceled {
                states[kind] = previous
            } catch {
                log.error("sign-in failed: \(kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                problems[kind] = Self.describe(error)
                if case AuthError.refused(let refusal) = error {
                    refusals[kind] = refusal
                }
                states[kind] = previous
            }
            pending[kind] = nil
        }
    }

    // allowLocalHTTP lets debug builds sign in to a CalDAV server on this Mac over plain http.
    #if DEBUG
    private static let allowLocalHTTP = true
    #else
    private static let allowLocalHTTP = false
    #endif

    // connectPassword checks the credentials against the service's server, or the typed one, and saves them
    // only when they work. It returns a sentence for the sheet when they do not.
    func connectPassword(
        _ kind: AccountKind, server typed: String, username: String, password: String
    ) async -> String? {
        guard kind.usesPassword, states[kind] != .signingIn else {
            return nil
        }
        guard let server = kind.server ?? PasswordSignIn.serverURL(typed, allowLocalHTTP: Self.allowLocalHTTP) else {
            return "Enter the server's address. It has to start with https://."
        }
        let previous = states[kind] ?? .signedOut
        states[kind] = .signingIn
        do {
            let (record, discovery) = try await PasswordSignIn.complete(
                kind: kind, server: server, username: username, password: password,
                client: passwordClient(kind, server: server, username: username, password: password)
            )
            try Keychain.save(record)
            attach(record, discovery: discovery)
            problems[kind] = nil
            passwordPrompt = nil
            refresh(force: true)
            return nil
        } catch {
            log.error("sign-in failed: \(kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            states[kind] = previous
            return Self.describe(error)
        }
    }

    // cancelSignIn abandons a sign-in in progress.
    func cancelSignIn(_ kind: AccountKind) {
        pending[kind]?.cancel()
    }

    // disconnect forgets a service's account and its events.
    func disconnect(_ kind: AccountKind) {
        Keychain.delete(kind)
        sessions[kind] = nil
        cache[kind] = nil
        problems[kind] = nil
        refusals[kind] = nil
        states[kind] = kind.usesPassword || providers[kind] != nil ? .signedOut : .notConfigured
        onChange?()
    }

    // refreshIfDue reads the services when the interval has passed.
    func refreshIfDue(now: Date) {
        if now.timeIntervalSince(lastRead) >= interval {
            refresh(force: false)
        }
    }

    // refresh reads every connected service and reports the new events through onChange.
    func refresh(force: Bool) {
        guard !reading, force || Date().timeIntervalSince(lastRead) >= interval, !sessions.isEmpty else {
            return
        }
        reading = true
        lastRead = Date()
        let now = Date()
        let from = now.addingTimeInterval(-3600)
        let to = now.addingTimeInterval(lookahead)
        let current = sessions
        Task {
            for (kind, session) in current {
                do {
                    cache[kind] = try await session.entries(from: from, to: to)
                    problems[kind] = nil
                    refusals[kind] = nil
                    states[kind] = .connected(await session.record.address)
                } catch let error as AuthError {
                    log.error("account needs sign-in: \(kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                    problems[kind] = Self.describe(error)
                    states[kind] = .needsSignIn(await session.record.address)
                } catch {
                    log.error("calendar read failed: \(kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                    problems[kind] = Self.describe(error)
                }
            }
            reading = false
            onChange?()
        }
    }

    // signIn opens the browser at the provider and waits for the redirect.
    private func signIn(_ provider: OAuthProvider) async throws -> AccountRecord {
        let pkce = PKCE.generate()
        let state = PKCE.randomToken(bytes: 16)
        let server = try LoopbackServer(kind: provider.kind, state: state)
        pending[provider.kind] = server
        let port = try await server.start()
        let redirect = provider.redirectURI(port: port)
        NSWorkspace.shared.open(provider.authorizationURL(pkce: pkce, state: state, redirectURI: redirect))
        let code = try await server.code()
        NSApp.activate()
        return try await SignIn.complete(
            provider: provider, code: code, pkce: pkce, redirectURI: redirect, client: client, now: Date()
        )
    }

    // attach starts a session for a stored record, reusing a password sign-in's discovery when given.
    private func attach(_ record: AccountRecord, discovery: CalDAVCalendar.Discovery? = nil) {
        if record.kind.usesPassword {
            var client: HTTPClient = self.client
            if case .password(let server, let username, let password) = record.credential {
                client = passwordClient(record.kind, server: server, username: username, password: password)
            }
            sessions[record.kind] = PasswordSession(record: record, client: client, discovery: discovery)
            states[record.kind] = .connected(record.address)
            return
        }
        guard let provider = providers[record.kind] else {
            return
        }
        let log = self.log
        sessions[record.kind] = RemoteAccount(provider: provider, record: record, client: client) { updated in
            do {
                try Keychain.save(updated)
            } catch {
                log.error("refresh token save failed: \(updated.kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        states[record.kind] = .connected(record.address)
    }

    // passwordClient returns the client a password service's requests go through: one that answers only that
    // server's challenge with the credential for a service that asks for one, and the shared client otherwise.
    private func passwordClient(_ kind: AccountKind, server: URL, username: String, password: String) -> HTTPClient {
        kind.answersChallenge ? URLSessionClient(server: server, username: username, password: password) : client
    }

    // describe turns an error into a short sentence for settings.
    private static func describe(_ error: Error) -> String {
        switch error {
        case AuthError.refused(let refusal):
            return refusal.message
        case AuthError.reauthorize:
            return "This account needs you to sign in again."
        case AuthError.noRefreshToken:
            return "The service didn't allow Sheepdog to stay signed in. Try connecting again."
        case AuthError.stateMismatch:
            return "The sign-in response didn't match. Try connecting again."
        case LoopbackError.timeout:
            return "The browser didn't come back within five minutes."
        case RemoteError.unauthorized:
            return "The server didn't accept that user name and password."
        case RemoteError.notCalDAV:
            return "That server didn't answer as a CalDAV calendar."
        case RemoteError.insecureURL:
            return "The server asked for your password without encryption, so Sheepdog stopped."
        case is KeychainError:
            return "Sheepdog couldn't save the sign-in in your Keychain."
        case RemoteError.server(let status) where status == 403:
            return "Your organization blocked calendar access for Sheepdog."
        case RemoteError.server(let status):
            return "The calendar service returned an error (\(status))."
        case is URLError:
            return "Couldn't reach the calendar service."
        default:
            return "Something went wrong: \(error.localizedDescription)"
        }
    }
}
