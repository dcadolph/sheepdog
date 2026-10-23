import Foundation
import Testing

@testable import SheepdogCore

// googleClient serves the calendar list, the primary calendar's events, an empty owned calendar and the profile.
// Any other calendar gets a 404, so reading a calendar the user does not own fails the test.
func googleClient() -> MockClient {
    MockClient { request, _ in
        let url = request.url?.absoluteString ?? ""
        let base = "https://www.googleapis.com/calendar/v3"
        if url.hasPrefix("\(base)/users/me/calendarList") {
            return .ok("google-calendars.json")
        }
        if url.hasPrefix("\(base)/calendars/me%40example.com/events?") {
            return .ok("google-events.json")
        }
        if url.hasPrefix("\(base)/calendars/team-oncall%23x%40group.calendar.google.com/events?") {
            return .json(#"{"items": []}"#)
        }
        if url == "\(base)/calendars/primary" {
            return .ok("google-primary.json")
        }
        return .json("{}", status: 404)
    }
}

// testGoogleEventsRequest checks calendar id escaping, the window and expansion of recurring events.
@Test func testGoogleEventsRequest() {
    let got = GoogleCalendar.eventsRequest(
        calendarID: "team-oncall#x@group.calendar.google.com",
        from: utc("2026-10-22T14:00:00Z"),
        to: utc("2026-10-23T02:00:00Z"),
        accessToken: "tok",
        pageToken: "p2"
    )
    #expect(got.url?.absoluteString.hasPrefix(
        "https://www.googleapis.com/calendar/v3/calendars/team-oncall%23x%40group.calendar.google.com/events?"
    ) == true)
    #expect(queryItems(got.url) == [
        "timeMin": "2026-10-22T14:00:00Z",
        "timeMax": "2026-10-23T02:00:00Z",
        "singleEvents": "true",
        "orderBy": "startTime",
        "maxResults": "250",
        "pageToken": "p2",
    ])
    #expect(got.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
}

// testGoogleOwned checks that only the primary and owned, shown calendars are read.
@Test func testGoogleOwned() throws {
    let page = try GoogleCalendar.decode(GoogleCalendar.CalendarPage.self, from: fixture("google-calendars.json"))
    let got = GoogleCalendar.owned(page.items).map(\.id)
    #expect(got == ["me@example.com", "team-oncall#x@group.calendar.google.com"])
}

// testGoogleFetch checks the mapping of every fixture event and that only owned calendars are read.
@Test func testGoogleFetch() async throws {
    let client = googleClient()
    let got = try await GoogleCalendar.fetch(
        client: client, accessToken: "tok", from: utc("2026-10-22T14:00:00Z"), to: utc("2026-10-23T02:00:00Z")
    )
    let want = [
        CalendarEntry( // Test 0: Meet call with an offset time. The room and the user are not counted.
            eventID: "google:meet1",
            title: "1:1",
            start: utc("2026-10-22T15:00:00Z"),
            end: utc("2026-10-22T15:30:00Z"),
            status: .accepted,
            attendeeCount: 2,
            url: URL(string: "https://meet.google.com/abc-defg-hij"),
            webURL: URL(string: "https://www.google.com/calendar/event?eid=bWVldDE")
        ),
        CalendarEntry( // Test 1: Zoom add-on link from the video entry point, not yet answered, no htmlLink.
            eventID: "google:zoom1",
            title: "Customer call",
            start: utc("2026-10-22T17:00:00Z"),
            end: utc("2026-10-22T18:00:00Z"),
            status: .pending,
            attendeeCount: 1,
            url: URL(string: "https://us02web.zoom.us/j/81234567890")
        ),
        CalendarEntry( // Test 2: All-day and transparent. The canceled and working location events are dropped.
            eventID: "google:allday1",
            title: "Conference",
            start: utc("2026-10-22T00:00:00Z"),
            end: utc("2026-10-23T00:00:00Z"),
            isAllDay: true,
            isFree: true,
            status: .unknown,
            attendeeCount: 0
        ),
        CalendarEntry( // Test 3: The user's own focus block with fractional seconds.
            eventID: "google:block1",
            title: "Deep work",
            start: utc("2026-10-22T19:00:00Z"),
            end: utc("2026-10-22T21:00:00Z"),
            status: .accepted,
            attendeeCount: 0
        ),
        CalendarEntry( // Test 4: Declined.
            eventID: "google:no1",
            title: "Optional town hall",
            start: utc("2026-10-22T21:00:00Z"),
            end: utc("2026-10-22T22:00:00Z"),
            status: .declined,
            attendeeCount: 0
        ),
    ]
    #expect(got == want)
    #expect(client.requests.count == 3)
}

// testGoogleFetchPages checks that a nextPageToken is followed and an endless one is cut off.
@Test func testGoogleFetchPages() async throws {
    let paged = MockClient { request, _ in
        let url = request.url?.absoluteString ?? ""
        if url.contains("calendarList") {
            return .json(#"{"items": [{"id": "me@example.com", "primary": true}]}"#)
        }
        if url.contains("pageToken=p2") {
            return .json(#"{"items": [{"id": "b", "summary": "B", "start": {"dateTime": "2026-10-22T16:00:00Z"}, "end": {"dateTime": "2026-10-22T17:00:00Z"}}]}"#)
        }
        return .json(#"{"items": [{"id": "a", "summary": "A", "start": {"dateTime": "2026-10-22T15:00:00Z"}, "end": {"dateTime": "2026-10-22T16:00:00Z"}}], "nextPageToken": "p2"}"#)
    }
    let got = try await GoogleCalendar.fetch(client: paged, accessToken: "tok", from: Date(), to: Date())
    #expect(got.map(\.eventID) == ["google:a", "google:b"])

    let endless = MockClient { request, _ in
        if request.url?.absoluteString.contains("calendarList") == true {
            return .json(#"{"items": [{"id": "me@example.com", "primary": true}]}"#)
        }
        return .json(#"{"items": [], "nextPageToken": "again"}"#)
    }
    await #expect(throws: RemoteError.tooManyPages) {
        _ = try await GoogleCalendar.fetch(client: endless, accessToken: "tok", from: Date(), to: Date())
    }
}

// testGoogleFetchUnauthorized checks that a rejected token surfaces as unauthorized.
@Test func testGoogleFetchUnauthorized() async {
    let client = MockClient { _, _ in .json("{}", status: 401) }
    await #expect(throws: RemoteError.unauthorized) {
        _ = try await GoogleCalendar.fetch(client: client, accessToken: "tok", from: Date(), to: Date())
    }
}

// testGoogleProfile checks that the primary calendar id is the account address.
@Test func testGoogleProfile() async throws {
    let got = try await GoogleCalendar.profile(client: googleClient(), accessToken: "tok")
    #expect(got == "me@example.com")
}

// testGoogleStatus checks every responseStatus value.
@Test func testGoogleStatus() {
    let cases: [(String?, CalendarEntry.ParticipationStatus)] = [
        ("accepted", .accepted), // Test 0: Accepted.
        ("tentative", .tentative), // Test 1: Tentative.
        ("declined", .declined), // Test 2: Declined.
        ("needsAction", .pending), // Test 3: Not answered.
        (nil, .unknown), // Test 4: Missing.
    ]
    for (response, want) in cases {
        #expect(GoogleCalendar.status(response) == want, "\(response ?? "nil")")
    }
}
