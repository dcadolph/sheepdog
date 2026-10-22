import Foundation
import Testing

@testable import SheepdogCore

// CountdownCase is one formatting expectation, with now given relative to the start.
struct CountdownCase: Sendable, CustomTestStringConvertible {
    // Offset is the start time minus now, in seconds.
    let offset: TimeInterval
    // WantClock is the expected clock string.
    let wantClock: String
    // WantPhrase is the expected phrase.
    let wantPhrase: String
    // WantShort is the expected compact label.
    let wantShort: String

    // testDescription labels the case in test output.
    var testDescription: String { "offset \(offset)" }
}

// countdownCases covers future, boundary, past, and hour-plus values.
let countdownCases: [CountdownCase] = [
    CountdownCase(offset: 272, wantClock: "4:32", wantPhrase: "Starts in 4:32", wantShort: "5m"), // Test 0: Minutes.
    CountdownCase(offset: 45, wantClock: "0:45", wantPhrase: "Starts in 0:45", wantShort: "45s"), // Test 1: Seconds.
    CountdownCase(offset: 0.4, wantClock: "0:01", wantPhrase: "Starts in 0:01", wantShort: "1s"), // Test 2: Rounds up.
    CountdownCase(offset: 0, wantClock: "0:00", wantPhrase: "Starting now", wantShort: "now"), // Test 3: Exactly now.
    CountdownCase(offset: -65, wantClock: "1:05", wantPhrase: "Started 1:05 ago", wantShort: "now"), // Test 4: Past.
    CountdownCase( // Test 5: Over an hour.
        offset: 3723, wantClock: "1:02:03", wantPhrase: "Starts in 1:02:03", wantShort: "63m"
    ),
]

// testCountdown checks each formatter against the same offsets.
@Test(arguments: countdownCases)
func testCountdown(test: CountdownCase) {
    let start = base.addingTimeInterval(test.offset)
    #expect(Countdown.clock(test.offset) == test.wantClock)
    #expect(Countdown.phrase(start: start, now: base) == test.wantPhrase)
    #expect(Countdown.short(start: start, now: base) == test.wantShort)
}

// testSettingsDecodeFillsDefaults checks that saved settings missing newer fields still load.
@Test func testSettingsDecodeFillsDefaults() throws {
    let data = Data(#"{"takeoverLead": 120, "maxSnoozes": 5}"#.utf8)
    let got = try JSONDecoder().decode(AlertSettings.self, from: data)
    var want = AlertSettings()
    want.takeoverLead = 120
    want.maxSnoozes = 5
    #expect(got == want)
}

// testSettingsRoundTrip checks that encoding then decoding preserves every field.
@Test func testSettingsRoundTrip() throws {
    var want = AlertSettings()
    want.warningLeads = [900]
    want.alarmOutput = .builtInSpeakers
    want.boostVolume = false
    want.includeTentative = true
    want.useMacCalendar = false
    let got = try JSONDecoder().decode(AlertSettings.self, from: JSONEncoder().encode(want))
    #expect(got == want)
}

// RemainingCase is one countdown ring expectation, with now given relative to the start.
struct RemainingCase: Sendable, CustomTestStringConvertible {
    // Offset is the start time minus now, in seconds.
    let offset: TimeInterval
    // Span is the full scale of the ring, in seconds.
    let span: TimeInterval
    // WantFraction is the expected share of the span left.
    let wantFraction: Double

    // testDescription labels the case in test output.
    var testDescription: String { "offset \(offset) span \(span)" }
}

// remainingCases covers the full, partial, empty, past, and degenerate ring.
let remainingCases: [RemainingCase] = [
    RemainingCase(offset: 60, span: 60, wantFraction: 1), // Test 0: Full at the lead.
    RemainingCase(offset: 45, span: 60, wantFraction: 0.75), // Test 1: Test the alarm opens at three quarters.
    RemainingCase(offset: 0, span: 60, wantFraction: 0), // Test 2: Empty at the start.
    RemainingCase(offset: -30, span: 60, wantFraction: 0), // Test 3: Past clamps to empty.
    RemainingCase(offset: 300, span: 60, wantFraction: 1), // Test 4: Early clamps to full.
    RemainingCase(offset: 30, span: 0, wantFraction: 0), // Test 5: Zero span.
    RemainingCase(offset: 30, span: -10, wantFraction: 0), // Test 6: Negative span.
]

// testRemaining checks the countdown ring fraction.
@Test(arguments: remainingCases)
func testRemaining(test: RemainingCase) {
    let start = base.addingTimeInterval(test.offset)
    #expect(Countdown.remaining(start: start, now: base, span: test.span) == test.wantFraction)
}
