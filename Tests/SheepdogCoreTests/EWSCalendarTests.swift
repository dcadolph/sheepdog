import Foundation
import Network
import Testing

@testable import SheepdogCore

// ewsServer is the test server's EWS endpoint.
let ewsServer = URL(string: "https://mail.example.com/EWS/Exchange.asmx")!

// ewsOperation returns the name of the operation inside a request's SOAP body.
func ewsOperation(_ request: URLRequest) -> String? {
    guard let envelope = request.httpBody.flatMap(CalDAVCalendar.XMLTree.parse),
          let body = envelope.child(EWSCalendar.soap, "Body")
    else {
        return nil
    }
    return body.children.first?.name
}

// ewsCalendarView returns the CalendarView element of a FindItem request.
func ewsCalendarView(_ request: URLRequest) -> CalDAVCalendar.DAVNode? {
    request.httpBody.flatMap(CalDAVCalendar.XMLTree.parse)?
        .child(EWSCalendar.soap, "Body")?
        .child(EWSCalendar.messages, "FindItem")?
        .child(EWSCalendar.messages, "CalendarView")
}

// ewsItemIDs returns the ids a GetItem request asks for.
func ewsItemIDs(_ request: URLRequest) -> [String] {
    let ids = request.httpBody.flatMap(CalDAVCalendar.XMLTree.parse)?
        .child(EWSCalendar.soap, "Body")?
        .child(EWSCalendar.messages, "GetItem")?
        .child(EWSCalendar.messages, "ItemIds")?
        .children(EWSCalendar.types, "ItemId") ?? []
    return ids.compactMap { $0.attributes["Id"] }
}

// ewsClient serves two FindItem pages, split at the review's start, and one GetItem batch.
func ewsClient() -> MockClient {
    MockClient { request, _ in
        switch ewsOperation(request) {
        case "FindItem":
            let start = ewsCalendarView(request)?.attributes["StartDate"]
            return .ok(start == "2026-10-22T19:00:00Z" ? "ews-finditem-page2.xml" : "ews-finditem-page1.xml")
        case "GetItem":
            return .ok("ews-getitem.xml")
        default:
            return .json("", status: 400)
        }
    }
}

// testEWSFindItemRequest checks the POST, the SOAP envelope and the calendar view over the window.
@Test func testEWSFindItemRequest() throws {
    let got = EWSCalendar.findItemRequest(
        server: ewsServer, from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z")
    )
    #expect(got.url == ewsServer)
    #expect(got.httpMethod == "POST")
    #expect(got.value(forHTTPHeaderField: "Content-Type") == "text/xml; charset=utf-8")
    #expect(got.value(forHTTPHeaderField: "Authorization") == nil)
    let view = try #require(ewsCalendarView(got))
    #expect(view.attributes == [
        "MaxEntriesReturned": "200", "StartDate": "2026-10-22T14:00:00Z", "EndDate": "2026-10-23T02:00:00Z",
    ])
    let body = bodyText(got)
    #expect(body.contains(#"<t:RequestServerVersion Version="Exchange2013"/>"#))
    #expect(body.contains(#"<m:FindItem Traversal="Shallow">"#))
    #expect(body.contains(#"<t:DistinguishedFolderId Id="calendar"/>"#))
}

// testEWSGetItemRequest checks the text body shape, every property and that ids are escaped.
@Test func testEWSGetItemRequest() throws {
    let got = EWSCalendar.getItemRequest(server: ewsServer, ids: ["AAMk+1/x=", #"odd"&<id>"#])
    #expect(ewsOperation(got) == "GetItem")
    #expect(ewsItemIDs(got) == ["AAMk+1/x=", #"odd"&<id>"#])
    let body = bodyText(got)
    #expect(body.contains("<t:BodyType>Text</t:BodyType>"))
    for field in EWSCalendar.fields {
        #expect(body.contains(#"<t:FieldURI FieldURI="\#(field)"/>"#))
    }
}

// testEWSFetch checks paging, batching, the mapping of every fixture item and that only reads are sent.
@Test func testEWSFetch() async throws {
    let client = ewsClient()
    let got = try await EWSCalendar.fetch(
        client: client, server: ewsServer, addresses: ["me@example.com"],
        from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z"),
        floating: TimeZone(identifier: "America/Chicago")!
    )
    let want = [
        CalendarEntry( // Test 0: Accepted occurrence with a join URL. The user is left out by address, any case.
            eventID: "ews:040000008200E00074C5B7101A82E00800000000standup",
            title: "Standup",
            start: utc("2026-10-22T14:30:00Z"),
            end: utc("2026-10-22T14:45:00Z"),
            status: .accepted,
            attendeeCount: 3,
            url: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_standup%40thread.v2/0"
                + "?context=%7b%22Tid%22%3a%22t1%22%7d"),
            location: "Teams",
            notes: "Daily standup. Dial in: +1 555 0100",
            webURL: URL(string: "https://mail.example.com/owa/?ItemID=AAMkAD-standup&exvsurl=1"
                + "&viewmodel=CalendarItemDetails")
        ),
        CalendarEntry( // Test 1: Tentative, escaped subject, the Teams link only in the text body.
            eventID: "ews:040000008200E00074C5B7101A82E00800000000review",
            title: "Design review & Q<4> plan",
            start: utc("2026-10-22T19:00:00Z"),
            end: utc("2026-10-22T20:00:00Z"),
            status: .tentative,
            attendeeCount: 1,
            notes: """
            ________________________________________________________________________________
            Microsoft Teams meeting
            Join on your computer, mobile app or room device
            Click here to join the meeting<https://teams.microsoft.com/l/meetup-join/19%3ameeting_review%40thread.v2/0\
            ?context=%7b%22Tid%22%3a%22t1%22%7d>
            Meeting ID: 123 456 789
            ________________________________________________________________________________
            """
        ),
        CalendarEntry( // Test 2: All-day in Chicago moved to midnight UTC, free, the user as organizer.
            eventID: "ews:040000008200E00074C5B7101A82E00800000000offsite",
            title: "Offsite",
            start: utc("2026-10-22T00:00:00Z"),
            end: utc("2026-10-23T00:00:00Z"),
            isAllDay: true,
            isFree: true,
            status: .accepted,
            attendeeCount: 0
        ),
        CalendarEntry( // Test 3: No response yet, no UID, fractional seconds. The user's EX address is not
            // known, so the user counts with the organizer. The canceled and the vanished items are left out.
            eventID: "ews:AAMkAD-oneonone",
            title: "1:1",
            start: utc("2026-10-22T22:00:00Z"),
            end: utc("2026-10-22T22:30:00Z"),
            status: .pending,
            attendeeCount: 2,
            location: "Room 4 (Zoom)",
            notes: "Zoom: https://example.zoom.us/j/123456789?pwd=abc"
        ),
    ]
    #expect(got == want)
    #expect(JoinLinkFinder.find(in: got[0])?.provider == .teams)
    #expect(JoinLinkFinder.find(in: got[1])?.web.absoluteString.hasPrefix(
        "https://teams.microsoft.com/l/meetup-join/19%3ameeting_review"
    ) == true)
    #expect(JoinLinkFinder.find(in: got[3])?.provider == .zoom)
    let requests = client.requests
    #expect(requests.map(ewsOperation) == ["FindItem", "FindItem", "GetItem"])
    #expect(requests.prefix(2).map { ewsCalendarView($0)?.attributes["StartDate"] } == [
        "2026-10-22T14:00:00Z", "2026-10-22T19:00:00Z",
    ])
    #expect(ewsItemIDs(requests[2]) == [
        "AAMkAD-standup+1/occ=", "AAMkAD-review", "AAMkAD-offsite", "AAMkAD-canceled", "AAMkAD-gone",
        "AAMkAD-oneonone",
    ])
    #expect(Set(requests.compactMap(\.httpMethod)) == ["POST"])
}

// testEWSFetchBatches checks that GetItem asks for at most twenty items at a time, in order.
@Test func testEWSFetchBatches() async throws {
    let ids = (0..<45).map { "item-\($0)" }
    let items = ids.map { #"<t:CalendarItem><t:ItemId Id="\#($0)"/></t:CalendarItem>"# }.joined()
    let page = #"""
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
    <m:FindItemResponse xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
    xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"><m:ResponseMessages>
    <m:FindItemResponseMessage ResponseClass="Success"><m:RootFolder IncludesLastItemInRange="true">
    <t:Items>\#(items)</t:Items></m:RootFolder></m:FindItemResponseMessage>
    </m:ResponseMessages></m:FindItemResponse></s:Body></s:Envelope>
    """#
    let empty = #"""
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
    <m:GetItemResponse xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
    <m:ResponseMessages/></m:GetItemResponse></s:Body></s:Envelope>
    """#
    let client = MockClient { request, _ in
        .json(ewsOperation(request) == "FindItem" ? page : empty)
    }
    let got = try await EWSCalendar.fetch(
        client: client, server: ewsServer, addresses: [], from: utc("2026-10-22T14:00:00Z"),
        to: utc("2026-10-23T02:00:00Z")
    )
    #expect(got.isEmpty)
    let batches = client.requests.filter { ewsOperation($0) == "GetItem" }.map(ewsItemIDs)
    #expect(batches.map(\.count) == [20, 20, 5])
    #expect(batches.flatMap { $0 } == ids)
}

// testEWSFetchStuckPage checks that a full page whose last start cannot move the view forward is an error.
@Test func testEWSFetchStuckPage() async {
    let client = MockClient { _, _ in .ok("ews-finditem-page1.xml") }
    await #expect(throws: RemoteError.tooManyPages) {
        _ = try await EWSCalendar.fetch(
            client: client, server: ewsServer, addresses: [], from: utc("2026-10-22T20:00:00Z"),
            to: utc("2026-10-23T02:00:00Z")
        )
    }
    #expect(client.requests.count == 1)
}

// EWSFailure is a server reply that a read must turn into an error.
struct EWSFailure: Sendable, CustomTestStringConvertible {
    // Name labels the case.
    let name: String
    // Reply is the answer to the first request.
    let reply: MockResponse
    // Want is the error the read throws.
    let want: RemoteError

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// ewsFailures lists the replies that must fail and how.
let ewsFailures: [EWSFailure] = [
    EWSFailure( // Test 0: Wrong password.
        name: "unauthorized", reply: .json("", status: 401), want: .unauthorized
    ),
    EWSFailure( // Test 1: A SOAP fault with the status Exchange sends.
        name: "fault 500", reply: MockResponse(body: fixture("ews-fault.xml"), status: 500),
        want: .server(status: 500)
    ),
    EWSFailure( // Test 2: A SOAP fault behind a success status.
        name: "fault 200", reply: .ok("ews-fault.xml"), want: .server(status: 500)
    ),
    EWSFailure( // Test 3: An error message for the mailbox reads like the other services' 403.
        name: "access denied", reply: .ok("ews-finditem-denied.xml"), want: .server(status: 403)
    ),
    EWSFailure( // Test 4: A web page instead of a SOAP reply.
        name: "html", reply: .json("<html><body>Sign in</body></html>"), want: .decode
    ),
    EWSFailure( // Test 5: A SOAP reply for another operation.
        name: "wrong operation", reply: .ok("ews-getitem.xml"), want: .decode
    ),
]

// testEWSFailures checks that every bad reply becomes the right error.
@Test(arguments: ewsFailures)
func testEWSFailures(test: EWSFailure) async {
    let client = MockClient { _, _ in test.reply }
    await #expect(throws: test.want) {
        _ = try await EWSCalendar.fetch(
            client: client, server: ewsServer, addresses: [], from: utc("2026-10-22T14:00:00Z"),
            to: utc("2026-10-23T02:00:00Z")
        )
    }
}

// testEWSDate checks the xs:dateTime forms Exchange sends.
@Test func testEWSDate() {
    #expect(EWSCalendar.date("2026-10-22T14:00:00Z") == utc("2026-10-22T14:00:00Z"))
    #expect(EWSCalendar.date(" 2026-10-22T14:00:00.0000000Z\n") == utc("2026-10-22T14:00:00Z"))
    #expect(EWSCalendar.date("2026-10-22T09:00:00-05:00") == utc("2026-10-22T14:00:00Z"))
    #expect(EWSCalendar.date("tomorrow") == nil)
}

// testEWSEndpoint checks that a bare server gets the standard EWS path and a typed path is kept.
@Test func testEWSEndpoint() {
    let url = { (text: String) in URL(string: text)! }
    #expect(EWSCalendar.endpoint(url("https://mail.example.com")) == ewsServer)
    #expect(EWSCalendar.endpoint(url("https://mail.example.com/")) == ewsServer)
    #expect(EWSCalendar.endpoint(url("https://mail.example.com:8443")) == url("https://mail.example.com:8443/EWS/Exchange.asmx"))
    #expect(EWSCalendar.endpoint(url("https://mail.example.com/ews/exchange.asmx")) == url("https://mail.example.com/ews/exchange.asmx"))
}

// CredentialCase is one challenge and how the delegate must answer it.
struct CredentialCase: Sendable, CustomTestStringConvertible {
    // Name labels the case.
    let name: String
    // Scheme is the challenge's protocol.
    let scheme: String
    // Host is the challenge's host.
    let host: String
    // Port is the challenge's port.
    let port: Int
    // Method is the authentication method.
    let method: String
    // Failures is the previous failure count.
    let failures: Int
    // WantDisposition is the answer.
    let wantDisposition: URLSession.AuthChallengeDisposition
    // WantCredential reports that the credential is handed over.
    let wantCredential: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// credentialCases lists challenges for a delegate set up for https://mail.example.com/EWS/Exchange.asmx.
let credentialCases: [CredentialCase] = [
    CredentialCase( // Test 0: Basic from the server.
        name: "basic", scheme: "https", host: "mail.example.com", port: 443,
        method: NSURLAuthenticationMethodHTTPBasic, failures: 0, wantDisposition: .useCredential, wantCredential: true
    ),
    CredentialCase( // Test 1: NTLM from the server, host in another case.
        name: "ntlm", scheme: "https", host: "MAIL.example.com", port: 443,
        method: NSURLAuthenticationMethodNTLM, failures: 0, wantDisposition: .useCredential, wantCredential: true
    ),
    CredentialCase( // Test 2: The password was refused once already.
        name: "refused", scheme: "https", host: "mail.example.com", port: 443,
        method: NSURLAuthenticationMethodNTLM, failures: 1, wantDisposition: .rejectProtectionSpace,
        wantCredential: false
    ),
    CredentialCase( // Test 3: Negotiate is passed over so the server falls back to NTLM.
        name: "negotiate", scheme: "https", host: "mail.example.com", port: 443,
        method: NSURLAuthenticationMethodNegotiate, failures: 0, wantDisposition: .rejectProtectionSpace,
        wantCredential: false
    ),
    CredentialCase( // Test 4: Another host, such as a redirect target.
        name: "other host", scheme: "https", host: "evil.example", port: 443,
        method: NSURLAuthenticationMethodHTTPBasic, failures: 0, wantDisposition: .performDefaultHandling,
        wantCredential: false
    ),
    CredentialCase( // Test 5: The same host over plain http.
        name: "plain http", scheme: "http", host: "mail.example.com", port: 80,
        method: NSURLAuthenticationMethodHTTPBasic, failures: 0, wantDisposition: .performDefaultHandling,
        wantCredential: false
    ),
    CredentialCase( // Test 6: The same host on another port.
        name: "other port", scheme: "https", host: "mail.example.com", port: 8443,
        method: NSURLAuthenticationMethodNTLM, failures: 0, wantDisposition: .performDefaultHandling,
        wantCredential: false
    ),
    CredentialCase( // Test 7: The server's certificate is left to the system.
        name: "server trust", scheme: "https", host: "mail.example.com", port: 443,
        method: NSURLAuthenticationMethodServerTrust, failures: 0, wantDisposition: .performDefaultHandling,
        wantCredential: false
    ),
]

// testCredentialDelegate checks that the password goes only to the server's own Basic or NTLM challenge, once.
@Test(arguments: credentialCases)
func testCredentialDelegate(test: CredentialCase) {
    let delegate = CredentialDelegate(
        server: ewsServer, credential: URLCredential(user: "me", password: "pw", persistence: .none)
    )
    let space = URLProtectionSpace(
        host: test.host, port: test.port, protocol: test.scheme, realm: nil, authenticationMethod: test.method
    )
    let (disposition, credential) = delegate.answer(space, previousFailureCount: test.failures)
    #expect(disposition == test.wantDisposition)
    #expect((credential != nil) == test.wantCredential)
}

// BasicServer is a loopback HTTP server that asks for Basic credentials and records what each request sent.
final class BasicServer: @unchecked Sendable {
    // listener accepts connections on 127.0.0.1.
    private let listener: NWListener
    // expected is the Authorization value that is accepted.
    private let expected: String
    // lock guards seen.
    private let lock = NSLock()
    // seen holds each request's Authorization value, or an empty string when it had none.
    private var seen: [String] = []

    // init creates a server that accepts one user name and password.
    init(username: String, password: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        expected = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    // authorizations returns what each request sent so far.
    var authorizations: [String] {
        lock.withLock { seen }
    }

    // start listens and returns the port.
    func start() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { [listener] state in
                let result: Result<Int, Error>?
                switch state {
                case .ready:
                    result = .success(Int(listener.port?.rawValue ?? 0))
                case .failed(let error):
                    result = .failure(error)
                default:
                    result = nil
                }
                guard let result else {
                    return
                }
                if once.claim() {
                    continuation.resume(with: result)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: .global())
        }
    }

    // stop closes the listener.
    func stop() {
        listener.cancel()
    }

    // serve reads one request and answers it.
    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        read(connection, buffer: Data())
    }

    // read gathers the headers and the body, then replies 401 with a Basic challenge or 200 with a body.
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else {
                return
            }
            let buffer = buffer + (data ?? Data())
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if done || error != nil {
                    connection.cancel()
                } else {
                    read(connection, buffer: buffer)
                }
                return
            }
            let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
            var headers: [String: String] = [:]
            for line in head.split(separator: "\r\n").dropFirst() {
                guard let colon = line.firstIndex(of: ":") else {
                    continue
                }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[line[..<colon].lowercased()] = value
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            if buffer.count - end.upperBound < length, !done, error == nil {
                read(connection, buffer: buffer)
                return
            }
            let authorization = headers["authorization"] ?? ""
            lock.withLock { seen.append(authorization) }
            let reply: String
            if authorization == expected {
                let body = "ok"
                reply = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Connection: close\r\n\r\n\(body)"
            } else {
                reply = "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"EWS\"\r\n"
                    + "Content-Length: 0\r\nConnection: close\r\n\r\n"
            }
            connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

// Once lets exactly one caller through.
final class Once: @unchecked Sendable {
    // lock guards done.
    private let lock = NSLock()
    // done reports that a caller already went through.
    private var done = false

    // claim returns true for the first caller only.
    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}

// basicServerRead posts one EWS request through a credentialed URLSessionClient and returns the status.
func basicServerRead(server: URL, username: String, password: String) async throws -> (String, Int) {
    var request = EWSCalendar.findItemRequest(
        server: server, from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z")
    )
    request.timeoutInterval = 10
    let (data, status) = try await URLSessionClient(server: server, username: username, password: password)
        .send(request)
    return (String(decoding: data, as: UTF8.self), status)
}

// testURLSessionClientBasic answers a real Basic challenge over loopback: the right password gets in after one
// challenge, a wrong one comes back as a 401 after one try, and a client set up for another port never sends it.
@Test func testURLSessionClientBasic() async throws {
    let server = try BasicServer(username: "me", password: "pw")
    let port = try await server.start()
    defer { server.stop() }
    let url = URL(string: "http://127.0.0.1:\(port)/EWS/Exchange.asmx")!
    let expected = "Basic " + Data("me:pw".utf8).base64EncodedString()

    let (body, status) = try await basicServerRead(server: url, username: "me", password: "pw")
    #expect(status == 200)
    #expect(body == "ok")
    #expect(server.authorizations == ["", expected])

    let (_, refused) = try await basicServerRead(server: url, username: "me", password: "wrong")
    #expect(refused == 401)
    let wrong = server.authorizations.dropFirst(2)
    #expect(wrong.filter { !$0.isEmpty } == ["Basic " + Data("me:wrong".utf8).base64EncodedString()])

    let elsewhere = URL(string: "http://127.0.0.1:\(port == 65535 ? port - 1 : port + 1)/EWS/Exchange.asmx")!
    var request = EWSCalendar.findItemRequest(
        server: url, from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z")
    )
    request.timeoutInterval = 10
    let (_, stranger) = try await URLSessionClient(server: elsewhere, username: "me", password: "pw").send(request)
    #expect(stranger == 401)
    #expect(server.authorizations.count > 2 + wrong.count)
    #expect(server.authorizations.dropFirst(2 + wrong.count).allSatisfy { $0.isEmpty })
}
