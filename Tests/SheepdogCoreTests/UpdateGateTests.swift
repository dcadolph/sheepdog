import Foundation
import Testing

@testable import SheepdogCore

// GateCase is one moment and whether the gate calls it quiet.
struct GateCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Idle is the seconds since the last input.
    var idle: TimeInterval = 120
    // Busy is the app-built busy flag.
    var busy = false
    // OffDuty reports whether the shift is over.
    var offDuty = false
    // StartsIn is the seconds from now until a meeting starts, nil for no meeting.
    var startsIn: TimeInterval?
    // Length is the meeting length in seconds.
    var length: TimeInterval = 1800
    // Want is whether the gate should be quiet.
    let want: Bool

    var testDescription: String { name }
}

let gateNow = Date(timeIntervalSince1970: 1_800_000_000)

let gateCases: [GateCase] = [
    GateCase(name: "quiet", want: true),
    GateCase(name: "idle 29", idle: 29, want: false),
    GateCase(name: "idle 30", idle: 30, want: true),
    GateCase(name: "meeting in 14 min", startsIn: 14 * 60, want: false),
    GateCase(name: "meeting in 16 min", startsIn: 16 * 60, want: true),
    GateCase(name: "meeting in progress", startsIn: -600, want: false),
    GateCase(name: "meeting ended a minute ago", startsIn: -1860, want: true),
    GateCase(name: "off duty", offDuty: true, want: false),
    GateCase(name: "busy", busy: true, want: false),
]

// testQuietGate checks the quiet gate across idle, meeting, duty, and busy moments.
@Test(arguments: gateCases)
func testQuietGate(_ c: GateCase) {
    let meetings = c.startsIn.map { start in
        [(start: gateNow.addingTimeInterval(start), end: gateNow.addingTimeInterval(start + c.length))]
    } ?? []
    let got = UpdateGate.quiet(
        idleSeconds: c.idle, busy: c.busy, offDuty: c.offDuty, meetings: meetings, now: gateNow)
    #expect(got == c.want)
}

// testInstallUpdatesDefault checks that settings saved before the toggle existed turn it on.
@Test func testInstallUpdatesDefault() throws {
    let empty = try JSONDecoder().decode(AlertSettings.self, from: Data("{}".utf8))
    #expect(empty.installUpdates)
    let old = try JSONDecoder().decode(
        AlertSettings.self, from: Data(#"{"checkForUpdates":false,"showPill":true}"#.utf8))
    #expect(old.installUpdates)
    #expect(!old.checkForUpdates)
}
