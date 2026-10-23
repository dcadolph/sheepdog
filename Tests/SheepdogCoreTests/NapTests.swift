import Foundation
import Testing

@testable import SheepdogCore

// NapCase is one expected nap end for a length started at a time of day.
struct NapCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Length is the chosen nap.
    let length: NapLength
    // Now is when the nap starts, in UTC.
    let now: String
    // WantUntil is when the nap should end, in UTC, or nil for a nap until Tug is woken.
    let wantUntil: String?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// napCases cover every length and the morning boundary.
let napCases: [NapCase] = [
    NapCase( // Test 0: One hour.
        name: "one hour", length: .oneHour, now: "2026-10-23 09:15", wantUntil: "2026-10-23 10:15"
    ),
    NapCase( // Test 1: Three hours.
        name: "three hours", length: .threeHours, now: "2026-10-23 09:15", wantUntil: "2026-10-23 12:15"
    ),
    NapCase( // Test 2: An evening nap until morning ends the next day.
        name: "morning from evening", length: .untilMorning, now: "2026-10-23 21:00", wantUntil: "2026-10-24 06:00"
    ),
    NapCase( // Test 3: A daytime nap until morning ends the next day.
        name: "morning from daytime", length: .untilMorning, now: "2026-10-23 09:15", wantUntil: "2026-10-24 06:00"
    ),
    NapCase( // Test 4: After midnight it ends the same morning.
        name: "morning after midnight", length: .untilMorning, now: "2026-10-23 02:30", wantUntil: "2026-10-23 06:00"
    ),
    NapCase( // Test 5: Exactly at the morning hour it ends the next morning.
        name: "morning at the hour", length: .untilMorning, now: "2026-10-23 06:00", wantUntil: "2026-10-24 06:00"
    ),
    NapCase( // Test 6: Just before the morning hour it ends a minute later.
        name: "morning just before", length: .untilMorning, now: "2026-10-23 05:59", wantUntil: "2026-10-23 06:00"
    ),
    NapCase( // Test 7: Until woken never ends on its own.
        name: "until woken", length: .untilWoken, now: "2026-10-23 09:15", wantUntil: nil
    ),
]

// testNapUntil checks when each nap ends.
@Test(arguments: napCases)
func testNapUntil(test: NapCase) {
    let got = Nap.until(test.length, now: stamp(test.now), calendar: utc)
    #expect(got == (test.wantUntil.map(stamp) ?? Nap.forever))
}

// testIsNapping checks the nap boundary, a missing nap and a nap until woken.
@Test func testIsNapping() {
    let until = stamp("2026-10-23 10:00")
    #expect(Nap.isNapping(until: until, now: stamp("2026-10-23 09:59")))
    #expect(!Nap.isNapping(until: until, now: until))
    #expect(!Nap.isNapping(until: until, now: stamp("2026-10-23 10:01")))
    #expect(!Nap.isNapping(until: nil, now: until))
    #expect(Nap.isNapping(until: Nap.forever, now: stamp("2036-10-23 10:00")))
}

// testMorningLabel checks that the label says this morning only between midnight and the morning hour.
@Test func testMorningLabel() {
    #expect(Nap.morningLabel(now: stamp("2026-10-23 02:30"), calendar: utc) == "Until this morning")
    #expect(Nap.morningLabel(now: stamp("2026-10-23 05:59"), calendar: utc) == "Until this morning")
    #expect(Nap.morningLabel(now: stamp("2026-10-23 06:00"), calendar: utc) == "Until tomorrow morning")
    #expect(Nap.morningLabel(now: stamp("2026-10-23 21:00"), calendar: utc) == "Until tomorrow morning")
}
