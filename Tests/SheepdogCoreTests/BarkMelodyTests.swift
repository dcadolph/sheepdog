import Foundation
import Testing

@testable import SheepdogCore

// MelodyCase is one expectation for BarkMelody.current.
struct MelodyCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Outfit is the active outfit.
    let outfit: Outfit?
    // Tunes is the holidayTunes setting.
    let tunes: Bool
    // Sound is the alarm sound setting.
    let sound: String
    // Want is the expected tune.
    let want: BarkMelody?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// melodyCases covers each outfit, no outfit, the switch, and the alarm sound rule.
let melodyCases: [MelodyCase] = [
    MelodyCase(name: "new years", outfit: .newYears, tunes: true, sound: "Tug Barking", want: .auldLangSyne),
    MelodyCase(name: "valentines", outfit: .valentines, tunes: true, sound: "Tug Barking", want: .sweetheart),
    MelodyCase(name: "st patricks", outfit: .stPatricks, tunes: true, sound: "Tug Barking",
               want: .irishWasherwoman),
    MelodyCase(name: "easter", outfit: .easter, tunes: true, sound: "Tug Barking", want: nil),
    MelodyCase(name: "halloween", outfit: .halloween, tunes: true, sound: "Tug Barking", want: .mountainKing),
    MelodyCase(name: "thanksgiving", outfit: .thanksgiving, tunes: true, sound: "Tug Barking",
               want: .overTheRiver),
    MelodyCase(name: "christmas", outfit: .christmas, tunes: true, sound: "Tug Barking", want: .jingleBells),
    MelodyCase(name: "no outfit", outfit: nil, tunes: true, sound: "Tug Barking", want: nil),
    MelodyCase(name: "switch off", outfit: .christmas, tunes: false, sound: "Tug Barking", want: nil),
    MelodyCase(name: "macOS sound", outfit: .christmas, tunes: true, sound: "Sosumi", want: nil),
    MelodyCase(name: "tug woof", outfit: .christmas, tunes: true, sound: "Tug Woof", want: .jingleBells),
]

// testBarkMelodyCurrent checks which tune plays for each setting combination.
@Test(arguments: melodyCases)
func testBarkMelodyCurrent(test: MelodyCase) {
    var settings = AlertSettings()
    settings.holidayTunes = test.tunes
    settings.alarmSound = test.sound
    #expect(BarkMelody.current(outfit: test.outfit, settings: settings) == test.want)
}

// testBarkMelodyOutfitsAreDistinct checks that every tune has its own outfit and resource name.
@Test func testBarkMelodyOutfitsAreDistinct() {
    #expect(Set(BarkMelody.allCases.map(\.outfit)).count == BarkMelody.allCases.count)
    #expect(Set(BarkMelody.allCases.map(\.resource)).count == BarkMelody.allCases.count)
    #expect(BarkMelody.jingleBells.resource == "melody-santa")
}

// melodySoundsDir is the repo's sounds folder, found from this file's path.
let melodySoundsDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("sounds")

// testBarkMelodyFileExists checks that each tune's recording is in the sounds folder.
@Test(arguments: BarkMelody.allCases)
func testBarkMelodyFileExists(melody: BarkMelody) {
    let url = melodySoundsDir.appendingPathComponent("\(melody.resource).caf")
    #expect(FileManager.default.fileExists(atPath: url.path))
}
