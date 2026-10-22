import Foundation
import Testing

@testable import SheepdogCore

// base is a fixed reference time so tests never depend on the clock.
let base = Date(timeIntervalSince1970: 2_000_000_000)

// meetingAt returns a 30 minute meeting that starts at base plus offset seconds.
func meetingAt(_ offset: TimeInterval, id: String = "m") -> Meeting {
    Meeting(id: id, title: id, start: base.addingTimeInterval(offset), end: base.addingTimeInterval(offset + 1800))
}

// StageCase is one stage expectation for a meeting starting at base.
struct StageCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Now is seconds relative to the meeting start.
    let now: TimeInterval
    // State is the user's history with the meeting.
    let state: MeetingState
    // WantStage is the expected stage.
    let wantStage: Stage

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// stageCases walks one meeting from far away through expiry.
let stageCases: [StageCase] = [
    StageCase(name: "far away", now: -3600, state: MeetingState(), wantStage: .idle), // Test 0: An hour out.
    StageCase(name: "just before first lead", now: -601, state: MeetingState(), wantStage: .idle), // Test 1: Edge.
    StageCase(name: "first lead", now: -600, state: MeetingState(), wantStage: .warning), // Test 2: T-10.
    StageCase(name: "between leads", now: -120, state: MeetingState(), wantStage: .warning), // Test 3: T-2.
    StageCase(name: "takeover lead", now: -60, state: MeetingState(), wantStage: .takeover), // Test 4: T-1.
    StageCase(name: "after start", now: 120, state: MeetingState(), wantStage: .takeover), // Test 5: T+2.
    StageCase(name: "expired", now: 600, state: MeetingState(), wantStage: .idle), // Test 6: Nag window over.
    StageCase( // Test 7: Joined meetings are silent.
        name: "joined", now: -30, state: MeetingState(resolution: .joined), wantStage: .idle
    ),
    StageCase( // Test 8: Skipped meetings are silent.
        name: "skipped", now: 30, state: MeetingState(resolution: .skipped), wantStage: .idle
    ),
    StageCase( // Test 9: A live snooze drops a takeover to a warning.
        name: "snoozed",
        now: -30,
        state: MeetingState(snoozedUntil: base.addingTimeInterval(10), snoozeCount: 1),
        wantStage: .warning
    ),
    StageCase( // Test 10: An ended snooze brings the takeover back.
        name: "snooze ended",
        now: 20,
        state: MeetingState(snoozedUntil: base.addingTimeInterval(10), snoozeCount: 1),
        wantStage: .takeover
    ),
    StageCase( // Test 11: A closed pill keeps the warning stage.
        name: "pill closed warning", now: -120, state: MeetingState(pillHidden: true), wantStage: .warning
    ),
    StageCase( // Test 12: A closed pill still lets the takeover through.
        name: "pill closed takeover", now: -60, state: MeetingState(pillHidden: true), wantStage: .takeover
    ),
]

// testStage checks the stage at each point in a meeting's life.
@Test(arguments: stageCases)
func testStage(test: StageCase) {
    let got = Escalation.stage(
        for: meetingAt(0),
        state: test.state,
        settings: AlertSettings(),
        now: base.addingTimeInterval(test.now)
    )
    #expect(got == test.wantStage)
}

// testSnoozeLimits checks snooze lengths before and after start and that the limit holds.
@Test func testSnoozeLimits() {
    let settings = AlertSettings()
    let meeting = meetingAt(0)

    let first = Escalation.snoozed(MeetingState(), meeting: meeting, settings: settings, now: base.addingTimeInterval(-30))
    #expect(first.snoozeCount == 1)
    #expect(first.snoozedUntil == base)

    let second = Escalation.snoozed(first, meeting: meeting, settings: settings, now: base.addingTimeInterval(5))
    #expect(second.snoozeCount == 2)
    #expect(second.snoozedUntil == base.addingTimeInterval(35))

    let third = Escalation.snoozed(second, meeting: meeting, settings: settings, now: base.addingTimeInterval(40))
    #expect(third == second)
    #expect(!Escalation.canSnooze(third, settings: settings))
}

// PillCase is one expectation for whether the countdown pill shows.
struct PillCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // ShowPill is the user's setting for the floating countdown.
    let showPill: Bool
    // State is the user's history with the meeting.
    let state: MeetingState
    // WantShows is whether the pill should be up.
    let wantShows: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// pillCases covers the setting and the close button.
let pillCases: [PillCase] = [
    PillCase(name: "default", showPill: true, state: MeetingState(), wantShows: true), // Test 0: Pill shows.
    PillCase(name: "setting off", showPill: false, state: MeetingState(), wantShows: false), // Test 1: Setting wins.
    PillCase( // Test 2: Closing hides it.
        name: "closed", showPill: true, state: MeetingState(pillHidden: true), wantShows: false
    ),
    PillCase( // Test 3: Closed with the setting off stays hidden.
        name: "closed and off", showPill: false, state: MeetingState(pillHidden: true), wantShows: false
    ),
]

// testShowsPill checks the countdown pill against the setting and the close button.
@Test(arguments: pillCases)
func testShowsPill(test: PillCase) {
    var settings = AlertSettings()
    settings.showPill = test.showPill
    #expect(Escalation.showsPill(test.state, settings: settings) == test.wantShows)
}

// testSnoozeReopensPill checks that a snooze brings a closed pill back as the countdown to the next takeover.
@Test func testSnoozeReopensPill() {
    let settings = AlertSettings()
    let state = MeetingState(pillHidden: true)
    let got = Escalation.snoozed(state, meeting: meetingAt(0), settings: settings, now: base.addingTimeInterval(-30))
    #expect(!got.pillHidden)
    #expect(got.resolution == nil)
}

// testQuietedKeepsTakeover checks that holding a place from the takeover stops only the sound, and
// that a snooze lets the next takeover bark again.
@Test func testQuietedKeepsTakeover() {
    let settings = AlertSettings()
    let quiet = Escalation.quieted(MeetingState())
    #expect(quiet.quieted)
    #expect(quiet.resolution == nil)
    let stage = Escalation.stage(for: meetingAt(0), state: quiet, settings: settings, now: base.addingTimeInterval(-30))
    #expect(stage == .takeover)
    let now = base.addingTimeInterval(-30)
    let snoozed = Escalation.snoozed(quiet, meeting: meetingAt(0), settings: settings, now: now)
    #expect(!snoozed.quieted)
}

// testClosedTakeoverFallsBackToPill checks that closing the takeover leaves the pill up until expiry.
@Test func testClosedTakeoverFallsBackToPill() {
    let settings = AlertSettings()
    let closed = Escalation.closedTakeover(MeetingState(pillHidden: true))
    #expect(closed.resolution == nil)
    #expect(Escalation.showsPill(closed, settings: settings))
    for (offset, want) in [(-30.0, Stage.warning), (120, .warning), (600, .idle)] {
        let now = base.addingTimeInterval(offset)
        let got = Escalation.stage(for: meetingAt(0), state: closed, settings: settings, now: now)
        #expect(got == want)
    }
}

// testSnoozeNeverOutlivesExpiry checks that a takeover cannot persist past the nag window.
@Test func testSnoozeNeverOutlivesExpiry() {
    let settings = AlertSettings()
    let state = MeetingState(snoozedUntil: base.addingTimeInterval(10_000), snoozeCount: 1)
    let got = Escalation.stage(for: meetingAt(0), state: state, settings: settings, now: base.addingTimeInterval(600))
    #expect(got == .idle)
}

// testCrossedWarning checks that each lead fires exactly once across consecutive ticks.
@Test func testCrossedWarning() {
    let settings = AlertSettings()
    let meeting = meetingAt(0)
    var fired: [TimeInterval] = []
    var previous = base.addingTimeInterval(-900)
    for second in stride(from: -899.0, through: 0, by: 1) {
        let now = base.addingTimeInterval(second)
        if Escalation.crossedWarning(for: meeting, settings: settings, previous: previous, now: now) {
            fired.append(second)
        }
        previous = now
    }
    #expect(fired == [-600, -300])
}

// testMostUrgent checks that the loudest stage wins and the earlier start breaks ties.
@Test func testMostUrgent() {
    let settings = AlertSettings()
    let now = base
    let warningSoon = meetingAt(240, id: "warning-soon")
    let warningLater = meetingAt(500, id: "warning-later")
    let takeover = meetingAt(30, id: "takeover")
    let joined = meetingAt(10, id: "joined")
    let states = ["joined": MeetingState(resolution: .joined)]

    let all = Escalation.mostUrgent([warningLater, warningSoon, takeover, joined], states: states, settings: settings, now: now)
    #expect(all?.meeting.id == "takeover")
    #expect(all?.stage == .takeover)

    let warnings = Escalation.mostUrgent([warningLater, warningSoon], states: [:], settings: settings, now: now)
    #expect(warnings?.meeting.id == "warning-soon")

    #expect(Escalation.mostUrgent([joined], states: states, settings: settings, now: now) == nil)
    #expect(Escalation.mostUrgent([], states: [:], settings: settings, now: now) == nil)
}

// FilterCase is one expectation for which calendar entries become meetings.
struct FilterCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Entry is the calendar entry under test.
    let entry: CalendarEntry
    // Settings are the filter settings.
    let settings: AlertSettings
    // WantMeeting reports whether the entry should become a meeting.
    let wantMeeting: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// entry returns a calendar entry starting at base with the given changes applied.
func entry(_ change: (inout CalendarEntry) -> Void = { _ in }) -> CalendarEntry {
    var value = CalendarEntry(eventID: "e", title: "Standup", start: base, end: base.addingTimeInterval(900))
    change(&value)
    return value
}

// settings returns default settings with the given changes applied.
func settings(_ change: (inout AlertSettings) -> Void) -> AlertSettings {
    var value = AlertSettings()
    change(&value)
    return value
}

// filterCases covers every rule that keeps an entry from alerting.
let filterCases: [FilterCase] = [
    FilterCase(name: "accepted", entry: entry(), settings: AlertSettings(), wantMeeting: true), // Test 0: Basic case.
    FilterCase( // Test 1: All-day events never alert.
        name: "all day", entry: entry { $0.isAllDay = true }, settings: AlertSettings(), wantMeeting: false
    ),
    FilterCase( // Test 2: Declined events never alert.
        name: "declined", entry: entry { $0.status = .declined }, settings: AlertSettings(), wantMeeting: false
    ),
    FilterCase( // Test 3: Free events never alert.
        name: "free", entry: entry { $0.isFree = true }, settings: AlertSettings(), wantMeeting: false
    ),
    FilterCase( // Test 4: Tentative events are skipped by default.
        name: "tentative default", entry: entry { $0.status = .tentative }, settings: AlertSettings(), wantMeeting: false
    ),
    FilterCase( // Test 5: Tentative events alert when included.
        name: "tentative included",
        entry: entry { $0.status = .tentative },
        settings: settings { $0.includeTentative = true },
        wantMeeting: true
    ),
    FilterCase( // Test 6: Solo events alert by default.
        name: "solo default", entry: entry { $0.attendeeCount = 0 }, settings: AlertSettings(), wantMeeting: true
    ),
    FilterCase( // Test 7: Solo events are skipped when attendees are required.
        name: "solo required",
        entry: entry { $0.attendeeCount = 0 },
        settings: settings { $0.requireAttendees = true },
        wantMeeting: false
    ),
    FilterCase( // Test 8: Pending invitations alert.
        name: "pending", entry: entry { $0.status = .pending }, settings: AlertSettings(), wantMeeting: true
    ),
]

// testMeetingFilter checks which entries become meetings.
@Test(arguments: filterCases)
func testMeetingFilter(test: FilterCase) {
    let got = Meeting(entry: test.entry, settings: test.settings)
    #expect((got != nil) == test.wantMeeting)
}

// testMeetingIDSeparatesRecurrences checks that instances of one recurring event get distinct ids.
@Test func testMeetingIDSeparatesRecurrences() {
    let first = Meeting(entry: entry(), settings: AlertSettings())
    let second = Meeting(entry: entry { $0.start = base.addingTimeInterval(86_400) }, settings: AlertSettings())
    #expect(first != nil && second != nil)
    #expect(first?.id != second?.id)
}

// testMeetingBlankTitle checks that a blank title gets a readable fallback.
@Test func testMeetingBlankTitle() {
    let got = Meeting(entry: entry { $0.title = "   " }, settings: AlertSettings())
    #expect(got?.title == "Untitled meeting")
}
