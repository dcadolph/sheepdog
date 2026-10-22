import Foundation
import Testing

@testable import SheepdogCore

// placeEnding returns a held note for a meeting that ends at base plus offset seconds.
func placeEnding(_ offset: TimeInterval, id: String = "p", resolution: Resolution? = nil, handedBack: TimeInterval? = nil) -> HeldPlace {
    HeldPlace(
        id: id,
        title: id,
        note: "note \(id)",
        savedAt: base.addingTimeInterval(offset - 1800),
        meetingEnd: base.addingTimeInterval(offset),
        resolution: resolution,
        handedBackAt: handedBack.map { base.addingTimeInterval($0) }
    )
}

// DueCase is one hand-back expectation for a meeting ending at base.
struct DueCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Place is the held note.
    let place: HeldPlace
    // Now is seconds relative to the meeting end.
    let now: TimeInterval
    // MicInUse reports whether the microphone is in use at now.
    let micInUse: Bool
    // WantDue is whether the note should come back.
    let wantDue: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// dueCases walks a held note through the end of its meeting.
let dueCases: [DueCase] = [
    DueCase( // Test 0: Held during the meeting.
        name: "during", place: placeEnding(0, resolution: .joined), now: -60, micInUse: false, wantDue: false
    ),
    DueCase( // Test 1: Back at the scheduled end when the mic is idle.
        name: "end mic idle", place: placeEnding(0, resolution: .joined), now: 0, micInUse: false, wantDue: true
    ),
    DueCase( // Test 2: An overrun call keeps the note held.
        name: "overrun", place: placeEnding(0, resolution: .joined), now: 600, micInUse: true, wantDue: false
    ),
    DueCase( // Test 3: The grace cap ends the wait even with the mic in use.
        name: "grace cap", place: placeEnding(0, resolution: .joined), now: 1800, micInUse: true, wantDue: true
    ),
    DueCase( // Test 4: Just before the grace cap.
        name: "before cap", place: placeEnding(0, resolution: .joined), now: 1799, micInUse: true, wantDue: false
    ),
    DueCase( // Test 5: A skipped meeting hands the note back at once.
        name: "skipped", place: placeEnding(0, resolution: .skipped), now: -1200, micInUse: true, wantDue: true
    ),
    DueCase( // Test 6: An unresolved meeting comes back at the end like a joined one.
        name: "unresolved", place: placeEnding(0), now: 0, micInUse: false, wantDue: true
    ),
    DueCase( // Test 7: A note already handed back stays due when the mic comes back on.
        name: "already back",
        place: placeEnding(0, resolution: .joined, handedBack: 0),
        now: 60,
        micInUse: true,
        wantDue: true
    ),
]

// testIsDue checks when a held note comes back.
@Test(arguments: dueCases)
func testIsDue(test: DueCase) {
    let got = PlaceKeeper.isDue(test.place, now: base.addingTimeInterval(test.now), micInUse: test.micInUse)
    #expect(got == test.wantDue)
}

// testHandedBackStampsOnce checks that a due note is stamped once and keeps its first stamp.
@Test func testHandedBackStampsOnce() {
    let places = [placeEnding(0, id: "a", resolution: .joined), placeEnding(3600, id: "b", resolution: .joined)]
    let first = PlaceKeeper.handedBack(places, now: base, micInUse: false)
    #expect(first[0].handedBackAt == base)
    #expect(first[1].handedBackAt == nil)
    let later = PlaceKeeper.handedBack(first, now: base.addingTimeInterval(60), micInUse: false)
    #expect(later[0].handedBackAt == base)
}

// testQueueOrder checks that only handed back notes queue, newest first.
@Test func testQueueOrder() {
    let places = [
        placeEnding(0, id: "late", handedBack: 120),
        placeEnding(0, id: "held"),
        placeEnding(0, id: "early", handedBack: 60),
    ]
    #expect(PlaceKeeper.queue(places).map(\.id) == ["late", "early"])
}

// testCleared checks that clearing drops every handed back note and keeps notes still held.
@Test func testCleared() {
    let places = [
        placeEnding(0, id: "late", handedBack: 120),
        placeEnding(0, id: "held"),
        placeEnding(0, id: "early", handedBack: 60),
    ]
    #expect(PlaceKeeper.cleared(places).map(\.id) == ["held"])
}

// ExpiryCase is one drop-time expectation.
struct ExpiryCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Place is the held note.
    let place: HeldPlace
    // WantExpiry is when the note should be dropped, as a UTC "yyyy-MM-dd HH:mm".
    let wantExpiry: String

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// stamp parses a UTC "yyyy-MM-dd HH:mm" string.
func stamp(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

// utc is a Gregorian calendar fixed to UTC so expiry tests never depend on the machine's zone.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

// expiryCases cover notes coming back at different times of day.
let expiryCases: [ExpiryCase] = [
    ExpiryCase( // Test 0: An afternoon hand-back lasts until the next morning.
        name: "afternoon",
        place: HeldPlace(
            id: "a", title: "a", note: "a", savedAt: stamp("2026-10-22 13:50"),
            meetingEnd: stamp("2026-10-22 14:30"), handedBackAt: stamp("2026-10-22 14:30")
        ),
        wantExpiry: "2026-10-23 04:00"
    ),
    ExpiryCase( // Test 1: A hand-back after midnight lasts until 4 a.m. that night.
        name: "after midnight",
        place: HeldPlace(
            id: "b", title: "b", note: "b", savedAt: stamp("2026-10-23 00:50"),
            meetingEnd: stamp("2026-10-23 01:30"), handedBackAt: stamp("2026-10-23 01:30")
        ),
        wantExpiry: "2026-10-23 04:00"
    ),
    ExpiryCase( // Test 2: A note still held expires after the latest time it could come back.
        name: "still held",
        place: HeldPlace(
            id: "c", title: "c", note: "c", savedAt: stamp("2026-10-22 02:30"),
            meetingEnd: stamp("2026-10-22 03:15")
        ),
        wantExpiry: "2026-10-22 04:00"
    ),
    ExpiryCase( // Test 3: The mic grace can carry a held note past 4 a.m. to the next day.
        name: "grace past four",
        place: HeldPlace(
            id: "d", title: "d", note: "d", savedAt: stamp("2026-10-22 03:00"),
            meetingEnd: stamp("2026-10-22 03:45")
        ),
        wantExpiry: "2026-10-23 04:00"
    ),
]

// testExpiry checks when notes are dropped.
@Test(arguments: expiryCases)
func testExpiry(test: ExpiryCase) {
    #expect(PlaceKeeper.expiry(of: test.place, calendar: utc) == stamp(test.wantExpiry))
}

// testPruned checks that expired notes are dropped and live ones kept.
@Test func testPruned() {
    let place = expiryCases[0].place
    #expect(PlaceKeeper.pruned([place], now: stamp("2026-10-23 03:59"), calendar: utc) == [place])
    #expect(PlaceKeeper.pruned([place], now: stamp("2026-10-23 04:00"), calendar: utc).isEmpty)
}

// testHeldPlaceRoundTrip checks that a held note survives encoding.
@Test func testHeldPlaceRoundTrip() throws {
    let place = placeEnding(0, resolution: .joined, handedBack: 30)
    let data = try JSONEncoder().encode([place])
    #expect(try JSONDecoder().decode([HeldPlace].self, from: data) == [place])
}

// testHoldPlaceDefault checks that settings saved before the hold setting existed turn it on.
@Test func testHoldPlaceDefault() throws {
    let settings = try JSONDecoder().decode(AlertSettings.self, from: Data("{}".utf8))
    #expect(settings.holdPlace)
}
