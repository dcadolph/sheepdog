import Foundation
import Testing

@testable import SheepdogCore

// caldavRoot is where the test server's discovery starts.
let caldavRoot = URL(string: "https://caldav.icloud.com/")!

// caldavDiscovery is what discovery finds on the test server.
let caldavDiscovery = CalDAVCalendar.Discovery(
    base: caldavRoot,
    home: URL(string: "https://p07-caldav.icloud.com:443/123456789/calendars/")!,
    addresses: ["me@icloud.com", "me@example.com"]
)

// caldavClient serves iCloud-shaped discovery, the calendar list and the work calendar's events. Any other
// request gets a 404, so asking for a skipped calendar fails the test.
func caldavClient() -> MockClient {
    MockClient { request, _ in
        let url = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? ""
        let depth = request.value(forHTTPHeaderField: "Depth") ?? ""
        switch (method, depth, url) {
        case ("PROPFIND", "0", "https://caldav.icloud.com/"):
            return MockResponse(body: fixture("caldav-principal.xml"), status: 207)
        case ("PROPFIND", "0", "https://caldav.icloud.com/123456789/principal/"):
            return MockResponse(body: fixture("caldav-home.xml"), status: 207)
        case ("PROPFIND", "1", "https://p07-caldav.icloud.com:443/123456789/calendars/"):
            return MockResponse(body: fixture("caldav-calendars.xml"), status: 207)
        case ("REPORT", "1", "https://p07-caldav.icloud.com:443/123456789/calendars/work/"):
            return MockResponse(body: fixture("caldav-events-work.xml"), status: 207)
        case ("REPORT", "1", "https://p07-caldav.icloud.com:443/123456789/calendars/home%20stuff/"):
            return MockResponse(body: fixture("caldav-empty.xml"), status: 207)
        default:
            return .json("", status: 404)
        }
    }
}

// testCalDAVPrincipalRequest checks the method, depth, Basic authorization and the property asked for.
@Test func testCalDAVPrincipalRequest() {
    let got = CalDAVCalendar.principalRequest(caldavRoot, username: "me@icloud.com", password: "abcd-efgh")
    #expect(got.httpMethod == "PROPFIND")
    #expect(got.value(forHTTPHeaderField: "Depth") == "0")
    #expect(got.value(forHTTPHeaderField: "Authorization") == "Basic bWVAaWNsb3VkLmNvbTphYmNkLWVmZ2g=")
    #expect(bodyText(got).contains("<D:current-user-principal/>"))
}

// testCalDAVEventsRequest checks that the window filters events and asks the server to expand recurrences.
@Test func testCalDAVEventsRequest() {
    let got = CalDAVCalendar.eventsRequest(
        calendar: URL(string: "https://p07-caldav.icloud.com/1/calendars/work/")!,
        from: utc("2026-10-22T14:00:00Z"),
        to: utc("2026-10-23T02:00:00Z"),
        username: "me@icloud.com",
        password: "pw"
    )
    let body = bodyText(got)
    #expect(got.httpMethod == "REPORT")
    #expect(got.value(forHTTPHeaderField: "Depth") == "1")
    #expect(body.contains(#"<C:expand start="20261022T140000Z" end="20261023T020000Z"/>"#))
    #expect(body.contains(#"<C:time-range start="20261022T140000Z" end="20261023T020000Z"/>"#))
    #expect(body.contains(#"<C:comp-filter name="VEVENT">"#))
}

// testCalDAVDiscover checks principal and home discovery, a home on another host and the address set.
@Test func testCalDAVDiscover() async throws {
    let got = try await CalDAVCalendar.discover(
        client: caldavClient(), base: caldavRoot, username: "Me@iCloud.com", password: "pw"
    )
    #expect(got == caldavDiscovery)
}

// testCalDAVDiscoverWellKnown checks the fallback to the well-known path when the typed URL is not CalDAV.
@Test func testCalDAVDiscoverWellKnown() async throws {
    let base = URL(string: "https://dav.example.com/remote.php/dav/")!
    let client = MockClient { request, _ in
        switch request.url?.absoluteString ?? "" {
        case "https://dav.example.com/.well-known/caldav":
            return .json(#"""
            <multistatus xmlns="DAV:"><response><href>/</href><propstat><prop>
            <current-user-principal><href>/principals/me/</href></current-user-principal>
            </prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
            """#, status: 207)
        case "https://dav.example.com/principals/me/":
            return .json(#"""
            <multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><response><href>/principals/me/</href>
            <propstat><prop><C:calendar-home-set><href>/calendars/me/</href></C:calendar-home-set></prop>
            <status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
            """#, status: 207)
        default:
            return .json("", status: 404)
        }
    }
    let got = try await CalDAVCalendar.discover(client: client, base: base, username: "me", password: "pw")
    #expect(got == CalDAVCalendar.Discovery(
        base: base, home: URL(string: "https://dav.example.com/calendars/me/")!, addresses: []
    ))
}

// CalDAVDiscoverFailure is a server reply discovery must turn into an error.
struct CalDAVDiscoverFailure: Sendable, CustomTestStringConvertible {
    // Name labels the case.
    let name: String
    // Base is where discovery starts.
    let base: String
    // Principal is the reply to every principal request.
    let principal: MockResponse
    // Home is the reply to the home request.
    let home: MockResponse
    // Want is the error discovery throws.
    let want: RemoteError

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// caldavDiscoverFailures lists the discovery replies that must fail and how.
let caldavDiscoverFailures: [CalDAVDiscoverFailure] = [
    CalDAVDiscoverFailure( // Test 0: Wrong password.
        name: "unauthorized", base: "https://caldav.icloud.com/",
        principal: .json("", status: 401), home: .json("", status: 404), want: .unauthorized
    ),
    CalDAVDiscoverFailure( // Test 1: Neither the URL nor the well-known path speaks CalDAV.
        name: "not caldav", base: "https://example.com/",
        principal: .json("", status: 404), home: .json("", status: 404), want: .notCalDAV
    ),
    CalDAVDiscoverFailure( // Test 2: A web page instead of a multistatus.
        name: "html", base: "https://example.com/",
        principal: .json("<html><body>Hi</body></html>"), home: .json("", status: 404), want: .notCalDAV
    ),
    CalDAVDiscoverFailure( // Test 3: The principal names a home over plain http on another host.
        name: "insecure home", base: "https://caldav.icloud.com/",
        principal: .ok("caldav-principal.xml"),
        home: .json(#"""
        <multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><response><href>/p/</href>
        <propstat><prop><C:calendar-home-set><href>http://evil.example/cal/</href></C:calendar-home-set></prop>
        <status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
        """#, status: 207),
        want: .insecureURL
    ),
    CalDAVDiscoverFailure( // Test 4: The principal has no home.
        name: "no home", base: "https://caldav.icloud.com/",
        principal: .ok("caldav-principal.xml"), home: .json(#"<multistatus xmlns="DAV:"/>"#, status: 207),
        want: .notCalDAV
    ),
    CalDAVDiscoverFailure( // Test 5: The server fails outright.
        name: "server error", base: "https://caldav.icloud.com/",
        principal: .json("", status: 503), home: .json("", status: 404), want: .server(status: 503)
    ),
]

// testCalDAVDiscoverFailures checks that every bad discovery reply becomes the right error.
@Test(arguments: caldavDiscoverFailures)
func testCalDAVDiscoverFailures(test: CalDAVDiscoverFailure) async {
    let client = MockClient { request, _ in
        request.value(forHTTPHeaderField: "Depth") == "0" && bodyText(request).contains("current-user-principal")
            ? test.principal : test.home
    }
    await #expect(throws: test.want) {
        _ = try await CalDAVCalendar.discover(
            client: client, base: URL(string: test.base)!, username: "me", password: "pw"
        )
    }
}

// testCalDAVCalendars checks that event calendars are kept and task, inbox and notification collections skipped.
@Test func testCalDAVCalendars() async throws {
    let got = try await CalDAVCalendar.calendars(
        client: caldavClient(), discovery: caldavDiscovery, username: "me", password: "pw"
    )
    #expect(got.map(\.absoluteString) == [
        "https://p07-caldav.icloud.com:443/123456789/calendars/work/",
        "https://p07-caldav.icloud.com:443/123456789/calendars/home%20stuff/",
    ])
}

// testCalDAVFetch checks the mapping of every fixture event and that only PROPFIND and REPORT are sent.
@Test func testCalDAVFetch() async throws {
    let client = caldavClient()
    let got = try await CalDAVCalendar.fetch(
        client: client, discovery: caldavDiscovery, username: "me", password: "pw",
        from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z"),
        floating: TimeZone(identifier: "Asia/Tokyo")!
    )
    let want = [
        CalendarEntry( // Test 0: Expanded recurring instance in a TZID zone. Room, self and the alarm are left out.
            eventID: "caldav:standup-uid",
            title: "Standup",
            start: utc("2026-10-22T14:30:00Z"),
            end: utc("2026-10-22T14:45:00Z"),
            status: .accepted,
            attendeeCount: 2,
            location: "https://example.zoom.us/j/987654321"
        ),
        CalendarEntry( // Test 1: All-day DATE event with no invitation.
            eventID: "caldav:offsite-uid",
            title: "Offsite",
            start: utc("2026-10-22T00:00:00Z"),
            end: utc("2026-10-23T00:00:00Z"),
            isAllDay: true,
            status: .unknown,
            attendeeCount: 0
        ),
        CalendarEntry( // Test 2: Folded description, escapes, quoted parameters and the user found by CN.
            eventID: "caldav:review-uid",
            title: "Design review, round 2",
            start: utc("2026-10-22T19:00:00Z"),
            end: utc("2026-10-22T20:00:00Z"),
            isFree: true,
            status: .tentative,
            attendeeCount: 1,
            notes: "Join with Google Meet: https://meet.google.com/abc-defg-hij\n"
                + "Or dial: +1 555 0100, PIN 123; ask & wait"
        ),
        CalendarEntry( // Test 3: CRLF lines, a DURATION instead of DTEND, and the user as organizer.
            eventID: "caldav:planning-uid",
            title: "Planning",
            start: utc("2026-10-22T21:00:00Z"),
            end: utc("2026-10-22T21:45:00Z"),
            status: .accepted,
            attendeeCount: 1,
            url: URL(string: "https://example.zoom.us/j/123456789?pwd=abc")
        ),
    ]
    #expect(got == want)
    #expect(JoinLinkFinder.find(in: got[2])?.web.absoluteString == "https://meet.google.com/abc-defg-hij")
    #expect(Set(client.requests.compactMap(\.httpMethod)) == ["PROPFIND", "REPORT"])
}

// testCalDAVFetchUnauthorized checks that a rejected password surfaces as unauthorized.
@Test func testCalDAVFetchUnauthorized() async {
    let client = MockClient { _, _ in .json("", status: 401) }
    await #expect(throws: RemoteError.unauthorized) {
        _ = try await CalDAVCalendar.fetch(
            client: client, discovery: caldavDiscovery, username: "me", password: "bad",
            from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z")
        )
    }
}

// testCalDAVFetchInsecureCalendar checks that a calendar href on plain http is refused before any read.
@Test func testCalDAVFetchInsecureCalendar() async {
    let client = MockClient { _, _ in
        .json(#"""
        <multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><response>
        <href>http://evil.example/cal/</href><propstat><prop><resourcetype><collection/><C:calendar/></resourcetype>
        </prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
        """#, status: 207)
    }
    await #expect(throws: RemoteError.insecureURL) {
        _ = try await CalDAVCalendar.fetch(
            client: client, discovery: caldavDiscovery, username: "me", password: "pw",
            from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z")
        )
    }
    #expect(client.requests.count == 1)
}

// testCalDAVCheckAllowed checks that credentials go only to https or to the exact origin discovery started from.
@Test func testCalDAVCheckAllowed() {
    let local = URL(string: "http://localhost:5232/")!
    let icloud = URL(string: "https://p07-caldav.icloud.com/x/")!
    #expect((try? CalDAVCalendar.checkAllowed(icloud, base: caldavRoot)) != nil)
    #expect((try? CalDAVCalendar.checkAllowed(URL(string: "http://localhost:5232/me/")!, base: local)) != nil)
    #expect((try? CalDAVCalendar.checkAllowed(URL(string: "http://localhost:8080/me/")!, base: local)) == nil)
    #expect((try? CalDAVCalendar.checkAllowed(URL(string: "http://caldav.icloud.com/")!, base: caldavRoot)) == nil)
}

// CalDAVDateCase is one DTSTART line and the time it means.
struct CalDAVDateCase: Sendable, CustomTestStringConvertible {
    // Line is the content line.
    let line: String
    // Want is the expected time, or nil when the value is unreadable.
    let want: Date?
    // WantDate reports a whole-day value.
    let wantDate: Bool

    // testDescription labels the case in test output.
    var testDescription: String { line }
}

// caldavDateCases lists DATE and DATE-TIME forms, read with Tokyo as the floating zone.
let caldavDateCases: [CalDAVDateCase] = [
    CalDAVDateCase( // Test 0: UTC.
        line: "DTSTART:20261022T150000Z", want: utc("2026-10-22T15:00:00Z"), wantDate: false
    ),
    CalDAVDateCase( // Test 1: Named zone in daylight time.
        line: "DTSTART;TZID=America/New_York:20261022T110000", want: utc("2026-10-22T15:00:00Z"), wantDate: false
    ),
    CalDAVDateCase( // Test 2: Quoted zone with a vendor prefix.
        line: #"DTSTART;TZID="/mozilla.org/20050126_1/Europe/London":20261022T160000"#,
        want: utc("2026-10-22T15:00:00Z"), wantDate: false
    ),
    CalDAVDateCase( // Test 3: Unknown zone falls back to floating.
        line: "DTSTART;TZID=Central Standard Time:20261023T000000", want: utc("2026-10-22T15:00:00Z"), wantDate: false
    ),
    CalDAVDateCase( // Test 4: Floating time.
        line: "DTSTART:20261023T000000", want: utc("2026-10-22T15:00:00Z"), wantDate: false
    ),
    CalDAVDateCase( // Test 5: Whole day.
        line: "DTSTART;VALUE=DATE:20261022", want: utc("2026-10-22T00:00:00Z"), wantDate: true
    ),
    CalDAVDateCase( // Test 6: Garbage.
        line: "DTSTART:tomorrow", want: nil, wantDate: false
    ),
]

// testCalDAVDate checks every DATE and DATE-TIME form.
@Test(arguments: caldavDateCases)
func testCalDAVDate(test: CalDAVDateCase) throws {
    let prop = try #require(CalDAVCalendar.property(test.line))
    let got = CalDAVCalendar.date(prop, floating: TimeZone(identifier: "Asia/Tokyo")!)
    #expect(got?.date == test.want)
    if test.want != nil {
        #expect(got?.isDate == test.wantDate)
    }
}

// testCalDAVDuration checks the DURATION forms.
@Test func testCalDAVDuration() {
    #expect(CalDAVCalendar.seconds("PT45M") == 2700)
    #expect(CalDAVCalendar.seconds("P1DT2H30M15S") == 95415)
    #expect(CalDAVCalendar.seconds("P1W") == 604_800)
    #expect(CalDAVCalendar.seconds("-PT15M") == -900)
    #expect(CalDAVCalendar.seconds("PT5") == nil)
    #expect(CalDAVCalendar.seconds("1H") == nil)
}

// testCalDAVProperty checks parameter parsing with quoted colons and semicolons.
@Test func testCalDAVProperty() {
    let got = CalDAVCalendar.property(#"attendee;CN="Lee; Pat: PM";partstat=ACCEPTED:mailto:pat@example.com"#)
    #expect(got == CalDAVCalendar.Property(
        name: "ATTENDEE", params: ["CN": "Lee; Pat: PM", "PARTSTAT": "ACCEPTED"], value: "mailto:pat@example.com"
    ))
    #expect(CalDAVCalendar.property("no colon here") == nil)
}

// testCalDAVUnescape checks the text escapes and that an unknown escape is kept.
@Test func testCalDAVUnescape() {
    #expect(CalDAVCalendar.unescape(#"a\, b\; c\\d\ne\Nf\x"#) == "a, b; c\\d\ne\nf\\x")
}
