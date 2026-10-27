import Foundation
import Network

import SheepdogCore

// LoopbackServer listens on the loopback interface for the one browser redirect that ends a sign-in.
// Its mutable state is only touched on queue.
final class LoopbackServer: @unchecked Sendable {
    // listener accepts connections on a random loopback port.
    private let listener: NWListener
    // queue serializes every callback and all mutable state.
    private let queue = DispatchQueue(label: "com.dcadolph.sheepdog.loopback")
    // state is the value the redirect must carry back.
    private let state: String
    // kind is the service signing in, used to sort a refusal.
    private let kind: AccountKind
    // ready resumes start once the listener has a port.
    private var ready: CheckedContinuation<UInt16, Error>?
    // waiter resumes code once the redirect arrives.
    private var waiter: CheckedContinuation<String, Error>?
    // result holds the outcome when it arrives before anyone waits.
    private var result: Result<String, Error>?
    // timeout is how long the browser has to come back.
    private let timeout: TimeInterval = 300

    // init prepares a listener restricted to the loopback interface.
    init(kind: AccountKind, state: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.acceptLocalOnly = true
        listener = try NWListener(using: parameters, on: .any)
        self.state = state
        self.kind = kind
    }

    // start begins listening and returns the port the redirect URI must use.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.ready = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    self?.listenerChanged(state)
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
                    self?.finish(.failure(LoopbackError.timeout))
                }
            }
        }
    }

    // code waits for the redirect and returns its authorization code.
    func code() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.result {
                    continuation.resume(with: result)
                } else {
                    self.waiter = continuation
                }
            }
        }
    }

    // cancel abandons the sign-in.
    func cancel() {
        queue.async {
            self.finish(.failure(LoopbackError.canceled))
        }
    }

    // listenerChanged resumes start when the listener is ready or has failed.
    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener.port?.rawValue {
                ready?.resume(returning: port)
            } else {
                ready?.resume(throwing: LoopbackError.noPort)
            }
            ready = nil
        case .failed(let error):
            ready?.resume(throwing: error)
            ready = nil
            finish(.failure(error))
        default:
            break
        }
    }

    // handle reads one request, answers it, and finishes the sign-in when it is the redirect.
    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data, let target = AuthorizationCallback.target(fromRequest: data) else {
                self.respond(connection, status: "400 Bad Request", page: nil)
                return
            }
            do {
                guard let code = try AuthorizationCallback.code(
                    fromTarget: target, expectedState: self.state, kind: self.kind
                ) else {
                    self.respond(connection, status: "404 Not Found", page: nil)
                    return
                }
                self.respond(connection, status: "200 OK", page: Self.successPage)
                self.finish(.success(code))
            } catch {
                self.respond(connection, status: "200 OK", page: Self.failurePage)
                self.finish(.failure(error))
            }
        }
    }

    // respond writes a minimal HTTP response and closes the connection.
    private func respond(_ connection: NWConnection, status: String, page: String?) {
        let body = Data((page ?? "").utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // finish records the outcome once, wakes any waiter and stops listening.
    private func finish(_ outcome: Result<String, Error>) {
        guard result == nil else {
            return
        }
        result = outcome
        waiter?.resume(with: outcome)
        waiter = nil
        ready?.resume(throwing: LoopbackError.canceled)
        ready = nil
        listener.cancel()
    }

    // successPage tells the user to return to Sheepdog.
    private static let successPage = page(
        heading: "Tug has your calendar.",
        message: "You're signed in. You can close this tab and go back to Sheepdog."
    )

    // failurePage tells the user the sign-in did not finish.
    private static let failurePage = page(
        heading: "That sign-in didn't finish.",
        message: "Close this tab and try again from Sheepdog's settings."
    )

    // page renders a fixed message as a small HTML page. Callers pass only constant text.
    private static func page(heading: String, message: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Sheepdog</title>
        <style>body{font:16px -apple-system,sans-serif;margin:15vh auto;max-width:28em;padding:0 1em;\
        color:#222;background:#fbf8f1}@media(prefers-color-scheme:dark){body{color:#eee;background:#1d1d1b}}</style>
        </head><body><h1>\(heading)</h1><p>\(message)</p></body></html>
        """
    }
}
