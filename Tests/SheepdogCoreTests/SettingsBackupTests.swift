import Foundation
import Testing

@testable import SheepdogCore

// BackupDecodeCase is one backup file reading expectation.
struct BackupDecodeCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // JSON is the file content.
    let json: String
    // WantMaxSnoozes is the expected maxSnoozes when the file loads.
    let wantMaxSnoozes: Int?
    // Want is the expected error, or nil when the file loads.
    let want: BackupError?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// backupDecodeCases covers a current file, an older sparse file, and every refusal.
let backupDecodeCases: [BackupDecodeCase] = [
    BackupDecodeCase( // Test 0: Current file loads.
        name: "current",
        json: #"{"app":"Sheepdog","version":1,"exported":"2026-10-23T18:00:00Z","settings":{"maxSnoozes":4}}"#,
        wantMaxSnoozes: 4, want: nil
    ),
    BackupDecodeCase( // Test 1: Older version with missing keys loads with defaults.
        name: "older sparse",
        json: #"{"app":"Sheepdog","version":0,"exported":"2026-10-23T18:00:00Z","settings":{}}"#,
        wantMaxSnoozes: AlertSettings().maxSnoozes, want: nil
    ),
    BackupDecodeCase( // Test 2: Another app's file is refused.
        name: "other app",
        json: #"{"app":"moorings","version":1,"exported":"2026-10-23T18:00:00Z","settings":{}}"#,
        wantMaxSnoozes: nil, want: .notSheepdog("moorings")
    ),
    BackupDecodeCase( // Test 3: A newer format is refused.
        name: "newer version",
        json: #"{"app":"Sheepdog","version":2,"exported":"2026-10-23T18:00:00Z","settings":{}}"#,
        wantMaxSnoozes: nil, want: .newerVersion(2)
    ),
    BackupDecodeCase( // Test 4: Junk is refused.
        name: "junk",
        json: "not json",
        wantMaxSnoozes: nil, want: .unreadable
    ),
    BackupDecodeCase( // Test 5: Bare settings without the header are refused.
        name: "no header",
        json: #"{"maxSnoozes":4}"#,
        wantMaxSnoozes: nil, want: .unreadable
    ),
    BackupDecodeCase( // Test 6: A header with broken settings is refused.
        name: "broken settings",
        json: #"{"app":"Sheepdog","version":1,"exported":"2026-10-23T18:00:00Z","settings":{"maxSnoozes":"four"}}"#,
        wantMaxSnoozes: nil, want: .unreadable
    ),
]

// testSettingsBackupDecode checks loading and refusing backup files.
@Test(arguments: backupDecodeCases)
func testSettingsBackupDecode(test: BackupDecodeCase) {
    do {
        let got = try SettingsBackup.decode(Data(test.json.utf8))
        #expect(test.want == nil)
        #expect(got.maxSnoozes == test.wantMaxSnoozes)
    } catch let error as BackupError {
        #expect(error == test.want)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

// testSettingsBackupRoundTrip checks that every setting, Slack channels included, survives export
// and import, and that the file names the app and version.
@Test func testSettingsBackupRoundTrip() throws {
    var settings = AlertSettings()
    settings.warningLeads = [900, 120]
    settings.maxSnoozes = 5
    settings.alarmOutput = .builtInSpeakers
    settings.slackChannels = [SlackChannel(name: "#team", link: "https://acme.slack.com/archives/C0123ABCD")]
    let data = try SettingsBackup.encode(settings, exported: Date(timeIntervalSince1970: 1_792_000_000))
    #expect(try SettingsBackup.decode(data) == settings)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""app" : "Sheepdog""#))
    #expect(text.contains(#""version" : 1"#))
}

// testSettingsBackupMissingShowOutfits checks that an export without showOutfits imports with
// outfits on and every other field intact.
@Test func testSettingsBackupMissingShowOutfits() throws {
    let json = #"{"app":"Sheepdog","version":1,"exported":"2026-10-23T18:00:00Z","settings":{"theme":"rubie","maxSnoozes":7,"holdPlace":false}}"#
    let got = try SettingsBackup.decode(Data(json.utf8))
    var want = AlertSettings()
    want.theme = .rubie
    want.maxSnoozes = 7
    want.holdPlace = false
    #expect(got.showOutfits)
    #expect(got == want)
}

// testSettingsBackupShowOutfitsOffRoundTrip checks that turning outfits off survives export and import.
@Test func testSettingsBackupShowOutfitsOffRoundTrip() throws {
    var settings = AlertSettings()
    settings.showOutfits = false
    let data = try SettingsBackup.encode(settings, exported: Date(timeIntervalSince1970: 1_792_000_000))
    let got = try SettingsBackup.decode(data)
    #expect(got.showOutfits == false)
    #expect(got == settings)
}
