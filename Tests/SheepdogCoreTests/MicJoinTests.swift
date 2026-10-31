import Foundation
import Testing

@testable import SheepdogCore

// micStart is the start of every meeting in the mic cases.
let micStart = Date(timeIntervalSince1970: 2_000_000_000)

// micMeeting returns a meeting starting at micStart.
func micMeeting(_ id: String) -> Meeting {
    Meeting(id: id, title: "Standup", start: micStart, end: micStart.addingTimeInterval(1800))
}

// MicJoinCase is one mic reading and the meeting it should count as joined.
struct MicJoinCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let Name: String
    // Meetings are the known meetings.
    let Meetings: [Meeting]
    // Resolved lists the meeting ids already joined.
    var Resolved: [String] = []
    // Running reports whether the mic is live at the judgment.
    let Running: Bool
    // StartedAt is the mic's last start, in seconds from micStart.
    let StartedAt: TimeInterval
    // Now is the judgment, in seconds from micStart.
    let Now: TimeInterval
    // WantID is the meeting expected back, nil for none.
    let WantID: String?

    // testDescription labels the case in test output.
    var testDescription: String { Name }
}

// micJoinCases run with earliestLead 600 and takeoverLead 60.
let micJoinCases: [MicJoinCase] = [
    MicJoinCase( // Test 0: Dictation at T-8 that ended before T-1 joins nothing.
        Name: "ended dictation", Meetings: [micMeeting("a")], Running: false, StartedAt: -480, Now: -60, WantID: nil
    ),
    MicJoinCase( // Test 1: A call started at T-5 still live at T-1 joins the meeting.
        Name: "call in window", Meetings: [micMeeting("a")], Running: true, StartedAt: -300, Now: -60, WantID: "a"
    ),
    MicJoinCase( // Test 2: A mic live since T-20, before the window opened, is another call.
        Name: "earlier call", Meetings: [micMeeting("a")], Running: true, StartedAt: -1200, Now: -60, WantID: nil
    ),
    MicJoinCase( // Test 3: Two meetings at the same start: only the first is joined.
        Name: "overlap", Meetings: [micMeeting("a"), micMeeting("b")], Running: true, StartedAt: -180, Now: -60,
        WantID: "a"
    ),
    MicJoinCase( // Test 4: A meeting already resolved is not joined again.
        Name: "resolved", Meetings: [micMeeting("a")], Resolved: ["a"], Running: true, StartedAt: -180, Now: -60,
        WantID: nil
    ),
    MicJoinCase( // Test 5: A call started at T+2 inside the nag window joins the meeting.
        Name: "after start", Meetings: [micMeeting("a")], Running: true, StartedAt: 120, Now: 120, WantID: "a"
    ),
    MicJoinCase( // Test 6: Before the takeover mark nothing is judged yet.
        Name: "before takeover", Meetings: [micMeeting("a")], Running: true, StartedAt: -180, Now: -120,
        WantID: nil
    ),
    MicJoinCase( // Test 7: An expired meeting is not joined.
        Name: "expired", Meetings: [micMeeting("a")], Running: true, StartedAt: 540, Now: 600, WantID: nil
    ),
    MicJoinCase( // Test 8: The earlier of two meetings in the window is joined.
        Name: "earliest", Meetings: [
            Meeting(id: "late", title: "Late", start: micStart.addingTimeInterval(60), end: micStart.addingTimeInterval(900)),
            micMeeting("a"),
        ], Running: true, StartedAt: -180, Now: 0, WantID: "a"
    ),
]

// testMicJoined checks which meeting a live mic counts as joined.
@Test(arguments: micJoinCases)
func testMicJoined(test: MicJoinCase) {
    var settings = AlertSettings()
    settings.warningLeads = [600, 300]
    settings.takeoverLead = 60
    var states: [String: MeetingState] = [:]
    for id in test.Resolved {
        states[id] = MeetingState(resolution: .joined)
    }
    let got = MicJoin.joined(
        test.Meetings, states: states, settings: settings, micRunning: test.Running,
        micStartedAt: micStart.addingTimeInterval(test.StartedAt), now: micStart.addingTimeInterval(test.Now))
    #expect(got?.id == test.WantID)
}

// testMicJoinedWithoutStart checks that a live mic with no recorded start joins nothing.
@Test func testMicJoinedWithoutStart() {
    let got = MicJoin.joined(
        [micMeeting("a")], states: [:], settings: AlertSettings(), micRunning: true, micStartedAt: nil,
        now: micStart.addingTimeInterval(-60))
    #expect(got == nil)
}
