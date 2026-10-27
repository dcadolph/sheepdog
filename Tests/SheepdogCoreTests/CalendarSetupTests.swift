import Foundation
import Testing

@testable import SheepdogCore

// setupDay is one day in seconds.
let setupDay: TimeInterval = 86400
// setupNow is the moment the setup tests evaluate facts.
let setupNow = Date(timeIntervalSince1970: 1_800_000_000)
// setupLocal is a local source holding one calendar.
let setupLocal = SetupSource(kind: .local, title: "On My Mac", calendarCount: 1)
// setupOutlook is the Outlook bundle id.
let setupOutlook = "com.microsoft.Outlook"

// SetupCase is one set of facts and the hints expected from them.
struct SetupCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Facts is the observed setup.
    let facts: SetupFacts
    // Want is the expected hints in order.
    let want: [SetupHint]

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// setupFacts builds facts that raise no hint, with overrides applied by the caller.
func setupFacts(_ edit: (inout SetupFacts) -> Void = { _ in }) -> SetupFacts {
    var facts = SetupFacts(sources: [setupLocal], now: setupNow)
    edit(&facts)
    return facts
}

// setupCases cover each hint rule and its boundaries.
let setupCases: [SetupCase] = [
    SetupCase(name: "quiet baseline", facts: setupFacts(), want: []), // Test 0: Nothing to say.
    SetupCase(name: "access denied",
        facts: setupFacts { $0.macCalendarAccess = .denied; $0.sources = [] },
        want: [.noAccess, .nothingConnected]), // Test 1: noAccess first.
    SetupCase(name: "denied but mac calendar off",
        facts: setupFacts { $0.macCalendarOn = false; $0.macCalendarAccess = .denied },
        want: []), // Test 2: Off source needs no access.
    SetupCase(name: "granted, no calendars", facts: setupFacts { $0.sources = [] },
        want: [.nothingConnected]), // Test 3: Nothing connected.
    SetupCase(name: "no calendars but kind connected",
        facts: setupFacts { $0.sources = []; $0.connectedKinds = [.google] },
        want: []), // Test 4: A connected kind counts.
    SetupCase(name: "outlook without microsoft",
        facts: setupFacts { $0.installedApps = [setupOutlook]; $0.availableKinds = [.microsoft] },
        want: [.outlookWithoutMicrosoft]), // Test 5: Hint.
    SetupCase(name: "outlook with microsoft connected",
        facts: setupFacts {
            $0.installedApps = [setupOutlook]
            $0.availableKinds = [.microsoft]
            $0.connectedKinds = [.microsoft]
        }, want: []), // Test 6: Connected.
    SetupCase(name: "outlook, microsoft unavailable",
        facts: setupFacts { $0.installedApps = [setupOutlook] },
        want: []), // Test 7: Cannot connect.
    SetupCase(name: "outlook with exchange source",
        facts: setupFacts {
            $0.installedApps = [setupOutlook]
            $0.availableKinds = [.microsoft]
            $0.sources = [setupLocal, SetupSource(kind: .exchange, title: "Work", calendarCount: 2)]
        }, want: []), // Test 8: Exchange present.
    SetupCase(name: "teams2 counts",
        facts: setupFacts {
            $0.installedApps = ["com.microsoft.teams2"]
            $0.availableKinds = [.microsoft]
        },
        want: [.outlookWithoutMicrosoft]), // Test 9: Teams app.
    SetupCase(name: "quiet week, never seen",
        facts: setupFacts { $0.firstRun = setupNow.addingTimeInterval(-8 * setupDay) },
        want: [.quietWeek]), // Test 10: Eight days, no meeting.
    SetupCase(name: "first run 3 days ago",
        facts: setupFacts { $0.firstRun = setupNow.addingTimeInterval(-3 * setupDay) },
        want: []), // Test 11: Too new.
    SetupCase(name: "quiet week, old meeting",
        facts: setupFacts {
            $0.firstRun = setupNow.addingTimeInterval(-30 * setupDay)
            $0.lastMeetingSeen = setupNow.addingTimeInterval(-7 * setupDay)
        }, want: [.quietWeek]), // Test 12: Boundary.
    SetupCase(name: "recent meeting",
        facts: setupFacts {
            $0.firstRun = setupNow.addingTimeInterval(-30 * setupDay)
            $0.lastMeetingSeen = setupNow.addingTimeInterval(-1 * setupDay)
        }, want: []), // Test 13: Meeting seen.
    SetupCase(name: "no first run",
        facts: setupFacts(), want: []), // Test 14: Nil first run.
]

// testSetupHints checks each hint rule.
@Test(arguments: setupCases)
func testSetupHints(test: SetupCase) {
    #expect(CalendarSetup.hints(test.facts) == test.want)
}

// testSetupHintActions checks the message, detail and action of each hint.
@Test func testSetupHintActions() {
    #expect(SetupHint.noAccess.action == .allowAccess)
    #expect(SetupHint.nothingConnected.action == .openCalendars)
    #expect(SetupHint.outlookWithoutMicrosoft.action == .openCalendars)
    #expect(SetupHint.quietWeek.action == .openCalendars)
    #expect(SetupHint.noAccess.message == "Tug can't see macOS Calendar.")
    #expect(SetupHint.nothingConnected.message == "Tug doesn't see any calendar yet.")
    #expect(SetupHint.quietWeek.message.hasPrefix("Tug hasn't seen a meeting in a week."))
    #expect(SetupHint.outlookWithoutMicrosoft.detail?.contains("Internet Accounts") == true)
    #expect(SetupHint.nothingConnected.detail?.contains("Internet Accounts") == true)
    #expect(SetupHint.noAccess.detail == nil)
    #expect(SetupHint.quietWeek.detail == nil)
}

// SetupNudgeCase is one nudge history and whether the user is due a notice after it.
struct SetupNudgeCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Shown lists the days after first sight on which the hints were shown.
    let shown: [Double]
    // Silence is true when the user silences the card after the history.
    let silence: Bool
    // Blocked is true when the caller forbids a notice.
    let blocked: Bool
    // Check is the day after first sight on which due is asked.
    let check: Double
    // Want is whether a notice is due.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// setupNudgeCases cover the schedule, the cap, silence, and blocking.
let setupNudgeCases: [SetupNudgeCase] = [
    SetupNudgeCase( // Test 0: Never shown.
        name: "at once", shown: [], silence: false, blocked: false, check: 0, want: true
    ),
    SetupNudgeCase( // Test 1: Too soon.
        name: "an hour after", shown: [0], silence: false, blocked: false, check: 1.0 / 24, want: false
    ),
    SetupNudgeCase( // Test 2: Reminder.
        name: "3 days after", shown: [0], silence: false, blocked: false, check: 3, want: true
    ),
    SetupNudgeCase( // Test 3: Capped.
        name: "after 3 reminders", shown: [0, 3, 6, 9], silence: false, blocked: false, check: 400, want: false
    ),
    SetupNudgeCase( // Test 4: Silence.
        name: "silenced", shown: [], silence: true, blocked: false, check: 0, want: false
    ),
    SetupNudgeCase( // Test 5: Blocked.
        name: "blocked", shown: [], silence: false, blocked: true, check: 0, want: false
    ),
]

// testSetupNudgeDue checks the reminder schedule.
@Test(arguments: setupNudgeCases)
func testSetupNudgeDue(test: SetupNudgeCase) {
    var nudge = SetupNudge()
    nudge.see(hints: [.nothingConnected])
    for day in test.shown {
        nudge.shown(now: setupNow.addingTimeInterval(day * setupDay))
    }
    if test.silence {
        nudge.silence()
    }
    let now = setupNow.addingTimeInterval(test.check * setupDay)
    #expect(nudge.due(now: now, blocked: test.blocked) == test.want)
}

// testSetupNudgeSilenceSurvivesNewHints checks that silence holds for a new hint set.
@Test func testSetupNudgeSilenceSurvivesNewHints() {
    var nudge = SetupNudge()
    nudge.see(hints: [.nothingConnected])
    nudge.silence()
    nudge.see(hints: [.noAccess])
    #expect(!nudge.due(now: setupNow, blocked: false))
}

// testSetupNudgeChangedHintsRestart checks that a changed non-empty set restarts the schedule.
@Test func testSetupNudgeChangedHintsRestart() {
    var nudge = SetupNudge()
    nudge.see(hints: [.nothingConnected])
    nudge.shown(now: setupNow)
    nudge.shown(now: setupNow.addingTimeInterval(3 * setupDay))
    let soon = setupNow.addingTimeInterval(4 * setupDay)
    #expect(!nudge.due(now: soon, blocked: false))
    nudge.see(hints: [.nothingConnected])
    #expect(nudge.reminders == 1)
    nudge.see(hints: [.noAccess, .nothingConnected])
    #expect(nudge.reminders == 0)
    #expect(nudge.lastShown == nil)
    #expect(nudge.due(now: soon, blocked: false))
}

// testSetupNudgeEmptyNeverDue checks that an empty hint set is never due.
@Test func testSetupNudgeEmptyNeverDue() {
    var nudge = SetupNudge()
    #expect(!nudge.due(now: setupNow, blocked: false))
    nudge.see(hints: [.quietWeek])
    nudge.see(hints: [])
    #expect(!nudge.due(now: setupNow, blocked: false))
}

// testSetupNudgeCodable checks that a nudge survives an encode and decode.
@Test func testSetupNudgeCodable() throws {
    var nudge = SetupNudge()
    nudge.see(hints: [.noAccess, .quietWeek])
    nudge.shown(now: setupNow)
    nudge.shown(now: setupNow.addingTimeInterval(3 * setupDay))
    nudge.silence()
    let data = try JSONEncoder().encode(nudge)
    let got = try JSONDecoder().decode(SetupNudge.self, from: data)
    #expect(got == nudge)
}
