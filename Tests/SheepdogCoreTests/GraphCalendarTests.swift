import Foundation
import Testing

@testable import SheepdogCore

// graphNext is the nextLink in graph-page1.json.
let graphNext = "https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=2026-10-22T14:00:00Z"
    + "&endDateTime=2026-10-23T02:00:00Z&$skip=4"

// graphClient serves the two calendarView pages and the profile.
func graphClient() -> MockClient {
    MockClient { request, _ in
        let url = request.url?.absoluteString ?? ""
        if url == graphNext {
            return .ok("graph-page2.json")
        }
        if url.hasPrefix("https://graph.microsoft.com/v1.0/me/calendarView") {
            return .ok("graph-page1.json")
        }
        if url.hasPrefix("https://graph.microsoft.com/v1.0/me?") {
            return .ok("graph-me.json")
        }
        return .json("{}", status: 404)
    }
}

// testGraphCalendarViewRequest checks the window, fields, paging size and headers.
@Test func testGraphCalendarViewRequest() {
    let got = GraphCalendar.calendarViewRequest(
        from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z"), accessToken: "tok"
    )
    #expect(got.url?.path == "/v1.0/me/calendarView")
    #expect(queryItems(got.url) == [
        "startDateTime": "2026-10-22T14:00:00Z",
        "endDateTime": "2026-10-23T02:00:00Z",
        "$select": GraphCalendar.fields.joined(separator: ","),
        "$orderby": "start/dateTime",
        "$top": "100",
    ])
    #expect(got.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(got.value(forHTTPHeaderField: "Prefer") == #"outlook.timezone="UTC", outlook.body-content-type="text""#)
}

// testGraphFetch checks paging and the mapping of every fixture event.
@Test func testGraphFetch() async throws {
    let client = graphClient()
    let got = try await GraphCalendar.fetch(
        client: client,
        accessToken: "tok",
        from: utc("2026-10-22T14:00:00Z"),
        to: utc("2026-10-23T02:00:00Z"),
        selfAddress: "me@example.com"
    )
    let want = [
        CalendarEntry( // Test 0: Teams meeting. Self and the room are not counted, the organizer is.
            eventID: "graph:AAMkStandup",
            title: "Platform standup",
            start: utc("2026-10-22T15:00:00Z"),
            end: utc("2026-10-22T15:15:00Z"),
            status: .accepted,
            attendeeCount: 3,
            url: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"),
            location: "Microsoft Teams Meeting",
            notes: "Join on your computer or mobile app"
        ),
        CalendarEntry( // Test 1: Declined and shown as free.
            eventID: "graph:AAMkDeclined",
            title: "Budget review",
            start: utc("2026-10-22T16:00:00Z"),
            end: utc("2026-10-22T17:00:00Z"),
            isFree: true,
            status: .declined,
            attendeeCount: 1,
            location: "",
            notes: ""
        ),
        CalendarEntry( // Test 2: All-day holiday. The canceled retro before it is dropped.
            eventID: "graph:AAMkHoliday",
            title: "Company holiday",
            start: utc("2026-10-23T00:00:00Z"),
            end: utc("2026-10-24T00:00:00Z"),
            isAllDay: true,
            status: .unknown,
            attendeeCount: 0
        ),
        CalendarEntry( // Test 3: Organized by the user, fractional seconds dropped, Zoom link left in the body.
            eventID: "graph:AAMkFocus",
            title: "  Design   sync ",
            start: utc("2026-10-22T20:30:00Z"),
            end: utc("2026-10-22T21:00:00Z"),
            status: .accepted,
            attendeeCount: 1,
            location: "Zoom",
            notes: "Join Zoom Meeting\nhttps://us02web.zoom.us/j/81234567890?pwd=XyZ123\nMeeting ID: 812 3456 7890"
        ),
        CalendarEntry( // Test 4: Tentative.
            eventID: "graph:AAMkMaybe",
            title: "Vendor demo",
            start: utc("2026-10-22T22:00:00Z"),
            end: utc("2026-10-22T23:00:00Z"),
            status: .tentative,
            attendeeCount: 1
        ),
    ]
    #expect(got == want)
    let requests = client.requests
    #expect(requests.count == 2)
    #expect(requests.last?.url?.absoluteString == graphNext)
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Prefer") == GraphCalendar.prefer })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok" })
    #expect(JoinLinkFinder.find(in: got[3])?.provider == .zoom)
}

// testGraphFetchWithoutSelf checks that an unknown address still counts the other invitees.
@Test func testGraphFetchWithoutSelf() async throws {
    let got = try await GraphCalendar.fetch(
        client: graphClient(), accessToken: "tok", from: Date(), to: Date(), selfAddress: nil
    )
    #expect(got.first?.attendeeCount == 4)
}

// GraphErrorCase is one failing calendarView expectation.
struct GraphErrorCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Reply is what every request returns.
    let reply: MockResponse
    // Want is the expected error.
    let want: RemoteError

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// graphErrorCases covers rejected tokens, server errors, bad bodies and endless paging.
let graphErrorCases: [GraphErrorCase] = [
    GraphErrorCase(name: "unauthorized", reply: .json("{}", status: 401), want: .unauthorized), // Test 0: Expired token.
    GraphErrorCase(name: "throttled", reply: .json("{}", status: 429), want: .server(status: 429)), // Test 1: Throttled.
    GraphErrorCase(name: "not json", reply: .json("<html>"), want: .decode), // Test 2: Bad body.
    GraphErrorCase(name: "endless", reply: .ok("graph-page1.json"), want: .tooManyPages), // Test 3: Always a nextLink.
]

// testGraphFetchErrors checks the error for each failure.
@Test(arguments: graphErrorCases)
func testGraphFetchErrors(test: GraphErrorCase) async {
    let reply = test.reply
    let client = MockClient { _, _ in reply }
    await #expect(throws: test.want) {
        _ = try await GraphCalendar.fetch(client: client, accessToken: "tok", from: Date(), to: Date(), selfAddress: nil)
    }
}

// testGraphProfile checks that the sign-in name stands in for a missing mail address.
@Test func testGraphProfile() async throws {
    let client = graphClient()
    let got = try await GraphCalendar.profile(client: client, accessToken: "tok")
    #expect(got == "me@example.com")
    #expect(client.requests.first?.url?.absoluteString == "https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName")
}

// testGraphStatus checks every response value.
@Test func testGraphStatus() {
    let cases: [(String?, CalendarEntry.ParticipationStatus)] = [
        ("accepted", .accepted), // Test 0: Accepted.
        ("organizer", .accepted), // Test 1: Organizer.
        ("tentativelyAccepted", .tentative), // Test 2: Tentative.
        ("declined", .declined), // Test 3: Declined.
        ("notResponded", .pending), // Test 4: No response yet.
        ("none", .unknown), // Test 5: No invitation.
        (nil, .unknown), // Test 6: Missing.
    ]
    for (response, want) in cases {
        #expect(GraphCalendar.status(response) == want, "\(response ?? "nil")")
    }
}

// testGraphDate checks zone conversion and malformed times.
@Test func testGraphDate() {
    typealias Zone = GraphCalendar.DateTimeZone
    let cases: [(Zone, Date?)] = [
        (Zone(dateTime: "2026-10-22T15:00:00.0000000", timeZone: "UTC"), utc("2026-10-22T15:00:00Z")), // Test 0: UTC.
        (Zone(dateTime: "2026-10-22T10:00:00.0000000", timeZone: "America/Chicago"), utc("2026-10-22T15:00:00Z")), // Test 1: CDT.
        (Zone(dateTime: "2026-12-22T10:00:00", timeZone: "America/Chicago"), utc("2026-12-22T16:00:00Z")), // Test 2: CST.
        (Zone(dateTime: "2026-10-22T15:00:00", timeZone: "Not/AZone"), utc("2026-10-22T15:00:00Z")), // Test 3: Unknown zone.
        (Zone(dateTime: "2026-10-22", timeZone: "UTC"), nil), // Test 4: Too short.
        (Zone(dateTime: "garbage-garbage-garbage", timeZone: "UTC"), nil), // Test 5: Not a time.
    ]
    for (value, want) in cases {
        #expect(GraphCalendar.date(value) == want, "\(value.dateTime) \(value.timeZone ?? "")")
    }
}
