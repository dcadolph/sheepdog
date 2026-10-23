import Foundation
import Testing

@testable import SheepdogCore

// chicago is a Gregorian calendar in a zone with daylight saving time.
let chicago: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}()

// hours returns enabled working hours from start to end, in hours, on the given weekdays.
func hours(_ start: Int, _ end: Int, _ weekdays: [Int] = [2, 3, 4, 5, 6], outside: OffHours = .silent) -> WorkingHours {
    var hours = WorkingHours()
    hours.enabled = true
    hours.start = start * 60
    hours.end = end * 60
    hours.weekdays = weekdays
    hours.outside = outside
    return hours
}

// ContainsCase is one moment checked against a set of working hours.
struct ContainsCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Hours are the working hours under test.
    let hours: WorkingHours
    // At is the moment, in UTC.
    let at: String
    // Calendar reads the moment's local wall clock.
    let calendar: Calendar
    // WantIn reports whether the moment should fall inside a shift.
    let wantIn: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// containsCases cover both edges, weekends, overnight shifts, a full-day shift and both DST changes. 2026-10-23
// is a Friday.
let containsCases: [ContainsCase] = [
    ContainsCase( // Test 0: A minute before the start.
        name: "before start", hours: hours(8, 18), at: "2026-10-23 07:59", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 1: The start is inside.
        name: "at start", hours: hours(8, 18), at: "2026-10-23 08:00", calendar: utc, wantIn: true
    ),
    ContainsCase( // Test 2: The last minute is inside.
        name: "before end", hours: hours(8, 18), at: "2026-10-23 17:59", calendar: utc, wantIn: true
    ),
    ContainsCase( // Test 3: The end is outside.
        name: "at end", hours: hours(8, 18), at: "2026-10-23 18:00", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 4: Saturday is not checked.
        name: "saturday", hours: hours(8, 18), at: "2026-10-24 10:00", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 5: Sunday is not checked.
        name: "sunday", hours: hours(8, 18), at: "2026-10-25 10:00", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 6: An overnight shift that starts Friday.
        name: "overnight friday", hours: hours(22, 6), at: "2026-10-23 23:00", calendar: utc, wantIn: true
    ),
    ContainsCase( // Test 7: Saturday morning belongs to Friday's shift.
        name: "overnight into saturday", hours: hours(22, 6), at: "2026-10-24 02:00", calendar: utc, wantIn: true
    ),
    ContainsCase( // Test 8: The overnight end is outside.
        name: "overnight end", hours: hours(22, 6), at: "2026-10-24 06:00", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 9: No shift starts Saturday night.
        name: "overnight saturday", hours: hours(22, 6), at: "2026-10-24 23:00", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 10: Monday morning belongs to Sunday, which is not checked.
        name: "overnight into monday", hours: hours(22, 6), at: "2026-10-26 02:00", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 11: Between an overnight shift's end and its start.
        name: "overnight gap", hours: hours(22, 6), at: "2026-10-23 21:59", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 12: Equal start and end make a full day.
        name: "full day", hours: hours(0, 0), at: "2026-10-23 23:59", calendar: utc, wantIn: true
    ),
    ContainsCase( // Test 13: A full-day shift ends at midnight.
        name: "full day end", hours: hours(0, 0), at: "2026-10-24 00:00", calendar: utc, wantIn: false
    ),
    ContainsCase( // Test 14: 08:00 CDT the day after spring forward.
        name: "spring start", hours: hours(8, 18), at: "2026-03-09 13:00", calendar: chicago, wantIn: true
    ),
    ContainsCase( // Test 15: 07:59 CDT the day after spring forward.
        name: "spring early", hours: hours(8, 18), at: "2026-03-09 12:59", calendar: chicago, wantIn: false
    ),
    ContainsCase( // Test 16: 08:00 CST the day after fall back.
        name: "fall start", hours: hours(8, 18), at: "2026-11-02 14:00", calendar: chicago, wantIn: true
    ),
    ContainsCase( // Test 17: 07:59 CST the day after fall back.
        name: "fall early", hours: hours(8, 18), at: "2026-11-02 13:59", calendar: chicago, wantIn: false
    ),
    ContainsCase( // Test 18: The second 01:30 on the fall back night is inside an overnight shift.
        name: "fall repeated hour", hours: hours(22, 6, Array(1...7)), at: "2026-11-01 07:30", calendar: chicago,
        wantIn: true
    ),
]

// testContains checks which moments fall inside a shift.
@Test(arguments: containsCases)
func testContains(test: ContainsCase) {
    #expect(test.hours.contains(stamp(test.at), calendar: test.calendar) == test.wantIn)
}

// testTreatment checks that only an enabled, non-full setting holds back meetings outside hours.
@Test func testTreatment() {
    let evening = stamp("2026-10-23 19:00")
    let morning = stamp("2026-10-23 09:00")
    #expect(WorkingHours().treatment(for: evening, calendar: utc) == .full)
    #expect(hours(8, 18, outside: .full).treatment(for: evening, calendar: utc) == .full)
    #expect(hours(8, 18, outside: .silent).treatment(for: evening, calendar: utc) == .silent)
    #expect(hours(8, 18, outside: .quiet).treatment(for: evening, calendar: utc) == .quiet)
    #expect(hours(8, 18, outside: .quiet).treatment(for: morning, calendar: utc) == .full)
    #expect(hours(8, 18).isOffDuty(now: evening, calendar: utc))
    #expect(!hours(8, 18).isOffDuty(now: morning, calendar: utc))
    #expect(!WorkingHours().isOffDuty(now: evening, calendar: utc))
}

// gateMeeting returns a half-hour meeting starting at a UTC time.
func gateMeeting(_ id: String, _ start: String) -> Meeting {
    Meeting(id: id, title: id, start: stamp(start), end: stamp(start).addingTimeInterval(1800))
}

// testGateLateSnooze checks that a 16:55 meeting snoozed past a 17:00 end still takes over, while a 17:05 meeting
// stays silent.
@Test func testGateLateSnooze() {
    let early = gateMeeting("early", "2026-10-23 16:55")
    let late = gateMeeting("late", "2026-10-23 17:05")
    let gated = hours(8, 17).gate([early, late], calendar: utc)
    #expect(gated.alerting == [early])
    #expect(gated.quiet.isEmpty)
    let now = stamp("2026-10-23 17:01")
    let snoozedOut = MeetingState(snoozedUntil: stamp("2026-10-23 16:59"), snoozeCount: 2)
    let got = Escalation.mostUrgent(
        gated.alerting, states: [early.id: snoozedOut], settings: AlertSettings(), now: now, quiet: gated.quiet
    )
    #expect(got?.meeting == early)
    #expect(got?.stage == .takeover)
}

// testGateQuiet checks that a quiet meeting stays listed but never passes the warning stage.
@Test func testGateQuiet() {
    let late = gateMeeting("late", "2026-10-23 19:00")
    let gated = hours(8, 18, outside: .quiet).gate([late], calendar: utc)
    #expect(gated.alerting == [late])
    #expect(gated.quiet == [late.id])
    let now = stamp("2026-10-23 18:59")
    let quiet = Escalation.mostUrgent(gated.alerting, states: [:], settings: AlertSettings(), now: now, quiet: gated.quiet)
    #expect(quiet?.stage == .warning)
    let loud = Escalation.mostUrgent(gated.alerting, states: [:], settings: AlertSettings(), now: now)
    #expect(loud?.stage == .takeover)
}

// testNextStart checks the next shift start across a weekend, on a start, with no weekdays and in a DST gap.
@Test func testNextStart() {
    #expect(hours(8, 18).nextStart(after: stamp("2026-10-23 18:30"), calendar: utc) == stamp("2026-10-26 08:00"))
    #expect(hours(8, 18).nextStart(after: stamp("2026-10-23 07:00"), calendar: utc) == stamp("2026-10-23 08:00"))
    #expect(hours(8, 18).nextStart(after: stamp("2026-10-23 08:00"), calendar: utc) == stamp("2026-10-26 08:00"))
    #expect(hours(22, 6).nextStart(after: stamp("2026-10-24 02:00"), calendar: utc) == stamp("2026-10-26 22:00"))
    #expect(hours(8, 18, []).nextStart(after: stamp("2026-10-23 18:30"), calendar: utc) == nil)
    var gap = hours(2, 4, Array(1...7))
    gap.start = 2 * 60 + 30
    // 02:30 does not exist on 2026-03-08 in Chicago, so the shift starts once the clocks have jumped.
    let got = gap.nextStart(after: stamp("2026-03-08 06:00"), calendar: chicago)
    #expect(got.map { $0 > stamp("2026-03-08 06:00") && $0 <= stamp("2026-03-08 08:30") } == true)
}

// testDecodeWorkingHours checks that old files fall back to hours off and bad values fall back per field.
@Test func testDecodeWorkingHours() throws {
    let old = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"maxSnoozes": 3}"#.utf8))
    #expect(old.workingHours == WorkingHours())
    #expect(old.maxSnoozes == 3)
    let bad = Data(#"{"enabled": true, "start": 5000, "end": -1, "weekdays": [0, 3, 3, 9, 2], "outside": "loud"}"#.utf8)
    let got = try JSONDecoder().decode(WorkingHours.self, from: bad)
    var want = WorkingHours()
    want.enabled = true
    want.weekdays = [2, 3]
    #expect(got == want)
}

// testBackupWorkingHours checks that working hours survive an export and import.
@Test func testBackupWorkingHours() throws {
    var settings = AlertSettings()
    settings.workingHours = hours(22, 6, [1, 7], outside: .quiet)
    let data = try SettingsBackup.encode(settings, exported: stamp("2026-10-23 18:00"))
    #expect(try SettingsBackup.decode(data) == settings)
}

// testNapUntilWork checks that a nap until morning ends when work starts, and falls back to the morning hour.
@Test func testNapUntilWork() {
    let friday = stamp("2026-10-23 21:00")
    #expect(Nap.until(.untilMorning, now: friday, calendar: utc, hours: hours(8, 18)) == stamp("2026-10-26 08:00"))
    #expect(Nap.morningLabel(now: friday, calendar: utc, hours: hours(8, 18)) == "Until work starts")
    #expect(Nap.until(.untilMorning, now: friday, calendar: utc, hours: hours(8, 18, [])) == stamp("2026-10-24 06:00"))
    #expect(Nap.morningLabel(now: friday, calendar: utc, hours: hours(8, 18, [])) == "Until tomorrow morning")
    #expect(Nap.until(.oneHour, now: friday, calendar: utc, hours: hours(8, 18)) == stamp("2026-10-23 22:00"))
}

// testHoverOffDuty checks that the off duty line sits between the nap and the next meeting.
@Test func testHoverOffDuty() {
    let next = hoverMeeting("Standup", 1200)
    let got = Hover.status(
        active: nil, next: next, napLine: "Napping until 9:57 AM", offDutyLine: "Off duty until Mon 8:00 AM", now: base
    )
    #expect(got == "Napping until 9:57 AM\nOff duty until Mon 8:00 AM\nNext: Standup in 20 min")
    #expect(Hover.status(active: next, next: nil, napLine: nil, offDutyLine: "Off duty", now: base) == "Standup starts in 20 min")
}
