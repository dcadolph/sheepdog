import Foundation
import Testing

@testable import SheepdogCore

// RelativeCase is one expected wording for a start given relative to now.
struct RelativeCase: Sendable, CustomTestStringConvertible {
    // Offset is the start time minus now, in seconds.
    let offset: TimeInterval
    // WantText is the expected wording.
    let wantText: String

    // testDescription labels the case in test output.
    var testDescription: String { "offset \(offset)" }
}

// relativeCases cover the minute and hour boundaries on both sides of the start.
let relativeCases: [RelativeCase] = [
    RelativeCase(offset: 7800, wantText: "in 2h 10m"), // Test 0: Hours and minutes.
    RelativeCase(offset: 7200, wantText: "in 2h"), // Test 1: Whole hours.
    RelativeCase(offset: 3601, wantText: "in 1h 1m"), // Test 2: Just over an hour rounds up.
    RelativeCase(offset: 3600, wantText: "in 1h"), // Test 3: Exactly an hour.
    RelativeCase(offset: 3599, wantText: "in 1h"), // Test 4: Just under an hour rounds up to it.
    RelativeCase(offset: 272, wantText: "in 5 min"), // Test 5: Minutes round up.
    RelativeCase(offset: 60, wantText: "in 1 min"), // Test 6: Exactly a minute.
    RelativeCase(offset: 59, wantText: "in under a minute"), // Test 7: Under a minute.
    RelativeCase(offset: 0.5, wantText: "in under a minute"), // Test 8: Just before the start.
    RelativeCase(offset: 0, wantText: "now"), // Test 9: Exactly the start.
    RelativeCase(offset: -59, wantText: "now"), // Test 10: Within a minute after the start.
    RelativeCase(offset: -60, wantText: "1 min ago"), // Test 11: A minute after.
    RelativeCase(offset: -299, wantText: "4 min ago"), // Test 12: Past minutes round down.
    RelativeCase(offset: -3900, wantText: "1h 5m ago"), // Test 13: Over an hour ago.
]

// testRelative checks the worded countdown.
@Test(arguments: relativeCases)
func testRelative(test: RelativeCase) {
    #expect(Countdown.relative(start: base.addingTimeInterval(test.offset), now: base) == test.wantText)
}

// HoverCase is one expected menu bar hover text.
struct HoverCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Active is the meeting being alerted for.
    let active: Meeting?
    // Next is the next meeting ahead.
    let next: Meeting?
    // NapLine is the nap's line while Tug sleeps.
    let napLine: String?
    // WantText is the expected hover text.
    let wantText: String

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// hoverMeeting returns a half-hour meeting that starts offset seconds after base.
func hoverMeeting(_ title: String, _ offset: TimeInterval) -> Meeting {
    let start = base.addingTimeInterval(offset)
    return Meeting(id: title, title: title, start: start, end: start.addingTimeInterval(1800))
}

// hoverCases cover every branch and the order between them.
let hoverCases: [HoverCase] = [
    HoverCase( // Test 0: Nothing ahead.
        name: "empty", active: nil, next: nil, napLine: nil, wantText: "No meetings in the next 12 hours"
    ),
    HoverCase( // Test 1: The next meeting.
        name: "next", active: nil, next: hoverMeeting("Standup", 7800), napLine: nil,
        wantText: "Next: Standup in 2h 10m"
    ),
    HoverCase( // Test 2: A nap with nothing ahead.
        name: "nap", active: nil, next: nil, napLine: "Napping until 9:57 AM", wantText: "Napping until 9:57 AM"
    ),
    HoverCase( // Test 3: A nap shows the meeting it will sleep through.
        name: "nap and next", active: nil, next: hoverMeeting("Standup", 1200), napLine: "Napping until 9:57 AM",
        wantText: "Napping until 9:57 AM\nNext: Standup in 20 min"
    ),
    HoverCase( // Test 4: An alert outranks the nap and the next meeting.
        name: "active first", active: hoverMeeting("Review", 240), next: hoverMeeting("Standup", 1200),
        napLine: "Napping until 9:57 AM", wantText: "Review starts in 4 min"
    ),
    HoverCase( // Test 5: An alert at the start.
        name: "active now", active: hoverMeeting("Review", -30), next: nil, napLine: nil,
        wantText: "Review is starting now"
    ),
    HoverCase( // Test 6: A nag after the start.
        name: "active late", active: hoverMeeting("Review", -300), next: nil, napLine: nil,
        wantText: "Review started 5 min ago"
    ),
    HoverCase( // Test 7: A long title is cut short.
        name: "long title", active: nil, next: hoverMeeting(String(repeating: "a", count: 60), 600), napLine: nil,
        wantText: "Next: \(String(repeating: "a", count: 47))… in 10 min"
    ),
]

// testHoverStatus checks the menu bar hover text.
@Test(arguments: hoverCases)
func testHoverStatus(test: HoverCase) {
    #expect(Hover.status(active: test.active, next: test.next, napLine: test.napLine, now: base) == test.wantText)
}
