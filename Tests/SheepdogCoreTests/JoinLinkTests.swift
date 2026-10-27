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
    JoinLinkCase( // Test 7: Slack huddle link in notes opens on the web, which hands off to the app.
        name: "slack huddle",
        text: "Huddle: https://app.slack.com/huddle/T0123ABCD/C0456EFGH, see you there",
        wantProvider: .slack,
        wantNative: "https://app.slack.com/huddle/T0123ABCD/C0456EFGH"
    ),
    JoinLinkCase( // Test 8: A Slack channel link is not a huddle.
        name: "slack channel",
        text: "https://app.slack.com/client/T0123ABCD/C0456EFGH",
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

// JoinRouteCase is one route-table expectation.
struct JoinRouteCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Text is the field text the link is found in.
    let text: String
    // Choice is the open choice applied to the link.
    let choice: JoinOpen
    // Want is the expected route.
    let want: JoinRoute

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// joinRouteCases pins every provider and choice cell of the route table.
let joinRouteCases: [JoinRouteCase] = [
    JoinRouteCase( // Test 0: Teams in the app uses msteams with the web fallback.
        name: "teams app",
        text: "https://teams.microsoft.com/meet/2847?p=abc",
        choice: .app,
        want: .open(
            URL(string: "msteams:/meet/2847?p=abc")!,
            fallback: URL(string: "https://teams.microsoft.com/meet/2847?p=abc")!)
    ),
    JoinRouteCase( // Test 1: Teams in the browser opens the web link.
        name: "teams browser",
        text: "https://teams.microsoft.com/meet/2847?p=abc",
        choice: .browser,
        want: .open(URL(string: "https://teams.microsoft.com/meet/2847?p=abc")!, fallback: nil)
    ),
    JoinRouteCase( // Test 2: Zoom in the app uses zoommtg with the web fallback.
        name: "zoom app",
        text: "https://us02web.zoom.us/j/81234567890?pwd=XyZ123",
        choice: .app,
        want: .open(
            URL(string: "zoommtg://us02web.zoom.us/join?action=join&confno=81234567890&pwd=XyZ123")!,
            fallback: URL(string: "https://us02web.zoom.us/j/81234567890?pwd=XyZ123")!)
    ),
    JoinRouteCase( // Test 3: Zoom in the browser uses the web client and keeps the password.
        name: "zoom browser",
        text: "https://us02web.zoom.us/j/81234567890?pwd=XyZ123",
        choice: .browser,
        want: .open(URL(string: "https://us02web.zoom.us/wc/join/81234567890?pwd=XyZ123")!, fallback: nil)
    ),
    JoinRouteCase( // Test 4: Zoom in the browser without a password has no query.
        name: "zoom browser no pwd",
        text: "https://zoom.us/j/123456789",
        choice: .browser,
        want: .open(URL(string: "https://zoom.us/wc/join/123456789")!, fallback: nil)
    ),
    JoinRouteCase( // Test 5: Zoom in the app without a password.
        name: "zoom app no pwd",
        text: "https://zoom.us/j/123456789",
        choice: .app,
        want: .open(
            URL(string: "zoommtg://zoom.us/join?action=join&confno=123456789")!,
            fallback: URL(string: "https://zoom.us/j/123456789")!)
    ),
    JoinRouteCase( // Test 6: Meet ignores the app choice.
        name: "meet app",
        text: "https://meet.google.com/abc-defg-hij",
        choice: .app,
        want: .open(URL(string: "https://meet.google.com/abc-defg-hij")!, fallback: nil)
    ),
    JoinRouteCase( // Test 7: Meet in the browser opens the web link.
        name: "meet browser",
        text: "https://meet.google.com/abc-defg-hij",
        choice: .browser,
        want: .open(URL(string: "https://meet.google.com/abc-defg-hij")!, fallback: nil)
    ),
    JoinRouteCase( // Test 8: Webex in the app hands the web link to the Webex app.
        name: "webex app",
        text: "https://acme.webex.com/meet/jdoe",
        choice: .app,
        want: .handTo(
            bundleID: JoinLink.webexBundleID,
            url: URL(string: "https://acme.webex.com/meet/jdoe")!,
            fallback: URL(string: "https://acme.webex.com/meet/jdoe")!)
    ),
    JoinRouteCase( // Test 9: Webex in the browser opens the web link.
        name: "webex browser",
        text: "https://acme.webex.com/meet/jdoe",
        choice: .browser,
        want: .open(URL(string: "https://acme.webex.com/meet/jdoe")!, fallback: nil)
    ),
    JoinRouteCase( // Test 10: Slack in the app hands the huddle to the Slack app.
        name: "slack app",
        text: "https://app.slack.com/huddle/T0123ABCD/C0456EFGH",
        choice: .app,
        want: .handTo(
            bundleID: JoinLink.slackBundleID,
            url: URL(string: "https://app.slack.com/huddle/T0123ABCD/C0456EFGH")!,
            fallback: URL(string: "https://app.slack.com/huddle/T0123ABCD/C0456EFGH")!)
    ),
    JoinRouteCase( // Test 11: Slack in the browser opens the web link.
        name: "slack browser",
        text: "https://app.slack.com/huddle/T0123ABCD/C0456EFGH",
        choice: .browser,
        want: .open(URL(string: "https://app.slack.com/huddle/T0123ABCD/C0456EFGH")!, fallback: nil)
    ),
]

// testJoinRoute checks the route for each provider and choice.
@Test(arguments: joinRouteCases)
func testJoinRoute(test: JoinRouteCase) throws {
    let link = try #require(JoinLinkFinder.find(in: test.text))
    #expect(link.route(test.choice) == test.want)
}

// testJoinRouteOther checks that a bare URL opens on the web for both choices.
@Test func testJoinRouteOther() {
    let url = URL(string: "https://example.com/standup")!
    let link = JoinLink(provider: .other, web: url, native: url)
    #expect(link.route(.app) == .open(url, fallback: nil))
    #expect(link.route(.browser) == .open(url, fallback: nil))
}

// testJoinOpensDefaults checks the defaults and the fixed browser providers.
@Test func testJoinOpensDefaults() {
    let opens = JoinOpens()
    #expect(opens.teams == .app)
    #expect(opens.zoom == .app)
    #expect(opens.webex == .app)
    #expect(opens.slack == .app)
    #expect(opens.choice(for: .meet) == .browser)
    #expect(opens.choice(for: .other) == .browser)
}
