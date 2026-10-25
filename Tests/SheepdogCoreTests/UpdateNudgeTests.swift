import Foundation
import Testing

@testable import SheepdogCore

// nudgeDay is one day in seconds.
let nudgeDay: TimeInterval = 86400
// nudgeStart is the moment a tag is first seen in the nudge tests.
let nudgeStart = Date(timeIntervalSince1970: 1_800_000_000)

// NudgeCase is one nudge history and whether the user is due a notice after it.
struct NudgeCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Shown lists the days after first sight on which the notice was shown.
    let shown: [Double]
    // Skip is true when the user skips the tag after the history.
    let skip: Bool
    // Blocked is true when the caller forbids a notice.
    let blocked: Bool
    // Check is the day after first sight on which due is asked.
    let check: Double
    // Want is whether a notice is due.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// nudgeCases cover the schedule, the cap, skipping, blocking, and a clock set back.
let nudgeCases: [NudgeCase] = [
    NudgeCase(name: "first sight", shown: [], skip: false, blocked: false, check: 0, want: true), // Test 0: Never shown.
    NudgeCase(name: "6 days", shown: [0], skip: false, blocked: false, check: 6, want: false), // Test 1: Too soon.
    NudgeCase(name: "7 days", shown: [0], skip: false, blocked: false, check: 7, want: true), // Test 2: First reminder.
    NudgeCase(name: "29 days after reminder 1", shown: [0, 7], skip: false, blocked: false, check: 36, want: false), // Test 3: Too soon.
    NudgeCase(name: "30 days after reminder 1", shown: [0, 7], skip: false, blocked: false, check: 37, want: true), // Test 4: Second reminder.
    NudgeCase(name: "after 3 reminders", shown: [0, 7, 37, 67], skip: false, blocked: false, check: 400, want: false), // Test 5: Capped.
    NudgeCase(name: "skipped", shown: [], skip: true, blocked: false, check: 0, want: false), // Test 6: Skip blocks.
    NudgeCase(name: "blocked", shown: [], skip: false, blocked: true, check: 0, want: false), // Test 7: Blocked.
    NudgeCase(name: "clock set back", shown: [10], skip: false, blocked: false, check: 5, want: true), // Test 8: Clock behind.
]

// testNudgeDue checks the reminder schedule.
@Test(arguments: nudgeCases)
func testNudgeDue(test: NudgeCase) {
    var nudge = UpdateNudge()
    nudge.see("v1.0.0", now: nudgeStart)
    for day in test.shown {
        nudge.shown(now: nudgeStart.addingTimeInterval(day * nudgeDay))
    }
    if test.skip {
        nudge.skip()
    }
    let now = nudgeStart.addingTimeInterval(test.check * nudgeDay)
    #expect(nudge.due(now: now, blocked: test.blocked) == test.want)
}

// testNudgeNewTagAfterSkip checks that a newer tag is due again and resets the count.
@Test func testNudgeNewTagAfterSkip() {
    var nudge = UpdateNudge()
    nudge.see("v1.0.0", now: nudgeStart)
    nudge.shown(now: nudgeStart)
    nudge.shown(now: nudgeStart.addingTimeInterval(7 * nudgeDay))
    nudge.skip()
    let later = nudgeStart.addingTimeInterval(8 * nudgeDay)
    #expect(!nudge.due(now: later, blocked: false))
    nudge.see("v1.1.0", now: later)
    #expect(nudge.reminders == 0)
    #expect(nudge.lastShown == nil)
    #expect(nudge.firstSeen == later)
    #expect(nudge.skipped == "v1.0.0")
    #expect(nudge.due(now: later, blocked: false))
}

// testNudgeSameTag checks that seeing the same tag again changes nothing.
@Test func testNudgeSameTag() {
    var nudge = UpdateNudge()
    nudge.see("v1.0.0", now: nudgeStart)
    nudge.shown(now: nudgeStart)
    let before = nudge
    nudge.see("v1.0.0", now: nudgeStart.addingTimeInterval(3 * nudgeDay))
    #expect(nudge == before)
}

// testNudgeBlockedKeepsValue checks that asking while blocked leaves the value equal.
@Test func testNudgeBlockedKeepsValue() {
    var nudge = UpdateNudge()
    nudge.see("v1.0.0", now: nudgeStart)
    let before = nudge
    #expect(!nudge.due(now: nudgeStart, blocked: true))
    #expect(nudge == before)
}

// testNudgeCodable checks that a nudge survives an encode and decode.
@Test func testNudgeCodable() throws {
    var nudge = UpdateNudge()
    nudge.see("v1.0.0", now: nudgeStart)
    nudge.shown(now: nudgeStart)
    nudge.shown(now: nudgeStart.addingTimeInterval(7 * nudgeDay))
    nudge.skip()
    let data = try JSONEncoder().encode(nudge)
    let got = try JSONDecoder().decode(UpdateNudge.self, from: data)
    #expect(got == nudge)
}
