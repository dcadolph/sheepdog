import Foundation
import Testing

@testable import SheepdogCore

// TugSoundCase is one settings-name lookup expectation.
struct TugSoundCase: Sendable, CustomTestStringConvertible {
    // Name is the sound name as stored in settings.
    let name: String
    // WantResource is the bundled file the name resolves to, or nil for a system sound.
    let wantResource: String?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// tugSoundCases covers each bark, a system sound, and near misses that must not match.
let tugSoundCases: [TugSoundCase] = [
    TugSoundCase(name: "Tug Woof", wantResource: "tug-woof"), // Test 0: Single bark.
    TugSoundCase(name: "Tug Barking", wantResource: "tug-barking"), // Test 1: Alarm loop.
    TugSoundCase(name: "Sosumi", wantResource: nil), // Test 2: System sound stays a system sound.
    TugSoundCase(name: "tug woof", wantResource: nil), // Test 3: Names are exact.
    TugSoundCase(name: "", wantResource: nil), // Test 4: Empty name.
]

// testTugSoundLookup checks that settings names resolve to the right bundled file.
@Test(arguments: tugSoundCases)
func testTugSoundLookup(test: TugSoundCase) {
    #expect(TugSound(rawValue: test.name)?.resource == test.wantResource)
}

// testTugSoundDefaults checks that fresh and legacy settings alert with Tug's barks.
@Test func testTugSoundDefaults() throws {
    let fresh = AlertSettings()
    #expect(fresh.chimeSound == TugSound.woof.rawValue)
    #expect(fresh.alarmSound == TugSound.barking.rawValue)

    let decoded = try JSONDecoder().decode(AlertSettings.self, from: Data("{}".utf8))
    #expect(decoded.chimeSound == TugSound.woof.rawValue)
    #expect(decoded.alarmSound == TugSound.barking.rawValue)

    let picked = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"alarmSound":"Sosumi"}"#.utf8))
    #expect(picked.alarmSound == "Sosumi")
}
