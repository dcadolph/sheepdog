import Foundation
import Testing

@testable import SheepdogCore

// JoinLinkCase is one join-link extraction expectation.
struct JoinLinkCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Text is the field text searched for a link.
    let text: String
    // WantProvider is the expected provider, or nil when no link should be found.
    let wantProvider: JoinLink.Provider?
    // WantNative is the expected native URL string.
    let wantNative: String?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// joinLinkCases covers each provider, surrounding noise, and text with no link.
let joinLinkCases: [JoinLinkCase] = [
    JoinLinkCase( // Test 0: Teams meetup link inside notes.
        name: "teams meetup",
        text: "Join: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d\nDial in",
        wantProvider: .teams,
        wantNative: "msteams:/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"
    ),
    JoinLinkCase( // Test 1: Teams short meet link.
        name: "teams meet",
        text: "https://teams.microsoft.com/meet/2847?p=abc",
        wantProvider: .teams,
        wantNative: "msteams:/meet/2847?p=abc"
    ),
    JoinLinkCase( // Test 2: Zoom link with password becomes a zoommtg URL.
        name: "zoom with pwd",
        text: "Zoom: https://us02web.zoom.us/j/81234567890?pwd=XyZ123.",
        wantProvider: .zoom,
        wantNative: "zoommtg://us02web.zoom.us/join?action=join&confno=81234567890&pwd=XyZ123"
    ),
    JoinLinkCase( // Test 3: Google Meet stays a web link.
        name: "meet",
        text: "Video call: https://meet.google.com/abc-defg-hij",
        wantProvider: .meet,
        wantNative: "https://meet.google.com/abc-defg-hij"
    ),
    JoinLinkCase( // Test 4: The earliest link in the text wins.
        name: "earliest wins",
        text: "https://meet.google.com/abc-defg-hij or https://zoom.us/j/123",
        wantProvider: .meet,
        wantNative: "https://meet.google.com/abc-defg-hij"
    ),
    JoinLinkCase( // Test 5: Plain text has no link.
        name: "no link",
        text: "Conference room 4B",
        wantProvider: nil,
        wantNative: nil
    ),
    JoinLinkCase( // Test 6: Empty text has no link.
        name: "empty",
        text: "",
        wantProvider: nil,
        wantNative: nil
    ),
]

// testJoinLinkFind checks link extraction from free text.
@Test(arguments: joinLinkCases)
func testJoinLinkFind(test: JoinLinkCase) {
    let got = JoinLinkFinder.find(in: test.text)
    #expect(got?.provider == test.wantProvider)
    #expect(got?.native.absoluteString == test.wantNative)
}

// testJoinLinkFieldOrder checks that the URL field beats location and notes, and that a bare URL is a fallback.
@Test func testJoinLinkFieldOrder() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var entry = CalendarEntry(
        eventID: "e",
        title: "t",
        start: start,
        end: start.addingTimeInterval(1800),
        url: URL(string: "https://zoom.us/j/111"),
        location: "https://meet.google.com/abc-defg-hij"
    )
    #expect(JoinLinkFinder.find(in: entry)?.provider == .zoom)

    entry.url = URL(string: "https://example.com/standup")
    #expect(JoinLinkFinder.find(in: entry)?.provider == .meet)

    entry.location = nil
    #expect(JoinLinkFinder.find(in: entry)?.provider == .other)

    entry.url = nil
    #expect(JoinLinkFinder.find(in: entry) == nil)
}
