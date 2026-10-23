import Foundation
import Testing

@testable import SheepdogCore

// SlackLinkCase is one channel link parsing expectation.
struct SlackLinkCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Text is the pasted link.
    let text: String
    // WantChannel is the expected channel id, or nil when the text is not a channel link.
    let wantChannel: String?
    // WantWeb is the expected web URL string.
    let wantWeb: String?
    // WantNative is the expected native URL string.
    let wantNative: String?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// slackLinkCases covers both link forms, surrounding noise, and links that are not channels.
let slackLinkCases: [SlackLinkCase] = [
    SlackLinkCase( // Test 0: Copy link form opens on the web.
        name: "archives",
        text: "https://acme.slack.com/archives/C0123ABCD",
        wantChannel: "C0123ABCD",
        wantWeb: "https://acme.slack.com/archives/C0123ABCD",
        wantNative: "https://acme.slack.com/archives/C0123ABCD"
    ),
    SlackLinkCase( // Test 1: A message link in the channel keeps only the channel.
        name: "archives message",
        text: "  https://acme.slack.com/archives/C0123ABCD/p1729612345000100\n",
        wantChannel: "C0123ABCD",
        wantWeb: "https://acme.slack.com/archives/C0123ABCD",
        wantNative: "https://acme.slack.com/archives/C0123ABCD"
    ),
    SlackLinkCase( // Test 2: Enterprise Grid host.
        name: "enterprise",
        text: "https://acme.enterprise.slack.com/archives/G0456EFGH",
        wantChannel: "G0456EFGH",
        wantWeb: "https://acme.enterprise.slack.com/archives/G0456EFGH",
        wantNative: "https://acme.enterprise.slack.com/archives/G0456EFGH"
    ),
    SlackLinkCase( // Test 3: Web client form carries the team, so it opens in the app.
        name: "client",
        text: "https://app.slack.com/client/T0123ABCD/C0456EFGH/thread/C0456EFGH-1729612345.000100",
        wantChannel: "C0456EFGH",
        wantWeb: "https://app.slack.com/client/T0123ABCD/C0456EFGH",
        wantNative: "slack://channel?team=T0123ABCD&id=C0456EFGH"
    ),
    SlackLinkCase( // Test 4: A huddle link is not a channel link.
        name: "huddle",
        text: "https://app.slack.com/huddle/T0123ABCD/C0456EFGH",
        wantChannel: nil,
        wantWeb: nil,
        wantNative: nil
    ),
    SlackLinkCase( // Test 5: Another host is rejected.
        name: "lookalike host",
        text: "https://acme.slack.com.example.org/archives/C0123ABCD",
        wantChannel: nil,
        wantWeb: nil,
        wantNative: nil
    ),
    SlackLinkCase( // Test 6: Plain http is rejected.
        name: "http",
        text: "http://acme.slack.com/archives/C0123ABCD",
        wantChannel: nil,
        wantWeb: nil,
        wantNative: nil
    ),
    SlackLinkCase( // Test 7: Text around the link is rejected, since settings expects the link alone.
        name: "surrounding text",
        text: "Team: https://acme.slack.com/archives/C0123ABCD",
        wantChannel: nil,
        wantWeb: nil,
        wantNative: nil
    ),
    SlackLinkCase( // Test 8: A channel name is not a link.
        name: "name only",
        text: "#team",
        wantChannel: nil,
        wantWeb: nil,
        wantNative: nil
    ),
    SlackLinkCase( // Test 9: Empty text.
        name: "empty",
        text: "",
        wantChannel: nil,
        wantWeb: nil,
        wantNative: nil
    ),
]

// testSlackLinkParse checks channel link parsing.
@Test(arguments: slackLinkCases)
func testSlackLinkParse(test: SlackLinkCase) {
    let got = SlackLink.parse(test.text)
    #expect(got?.channelID == test.wantChannel)
    #expect(got?.web.absoluteString == test.wantWeb)
    #expect(got?.native.absoluteString == test.wantNative)
}

// testTeamMessageText checks both messages and the blank title fallback.
@Test func testTeamMessageText() {
    #expect(TeamMessage.runningLate.text(title: " Design review ") == "Running a few minutes late to Design review.")
    #expect(TeamMessage.cantMake.text(title: "Design review") == "I can't make Design review.")
    #expect(TeamMessage.runningLate.text(title: "  ") == "Running a few minutes late to the meeting.")
}

// testSlackChannelLabel checks the typed name, then the channel id, then a generic label.
@Test func testSlackChannelLabel() {
    #expect(SlackChannel(name: " #team ", link: "").label == "#team")
    #expect(SlackChannel(name: "", link: "https://acme.slack.com/archives/C0123ABCD").label == "C0123ABCD")
    #expect(SlackChannel(name: "", link: "nope").label == "Slack")
}

// testSlackSettings checks that old settings decode with no channels, that channels round-trip, and
// that only valid channels are offered.
@Test func testSlackSettings() throws {
    let old = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"maxSnoozes":3}"#.utf8))
    #expect(old.slackChannels.isEmpty)
    #expect(old.validSlackChannels.isEmpty)

    var settings = AlertSettings()
    settings.slackChannels = [
        SlackChannel(name: "#team", link: "https://acme.slack.com/archives/C0123ABCD"),
        SlackChannel(name: "#typo", link: "acme.slack.com/archives"),
    ]
    let decoded = try JSONDecoder().decode(AlertSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
    #expect(decoded.validSlackChannels.map(\.name) == ["#team"])
}
