import Foundation
import Testing

@testable import SheepdogCore

// PlaceCase is one bundle path and where it should count as installed.
struct PlaceCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Bundle is the running bundle's path.
    let bundle: String
    // Quarantined reports whether the bundle carries the download quarantine flag.
    let quarantined: Bool
    // Want is the expected place.
    let want: InstallPlace

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// installImage is the mounted release disk image the cases share.
let installImage = MountedImage(image: "/Users/me/Downloads/sheepdog_macos_universal.dmg", mount: "/Volumes/Sheepdog")

// placeCases cover each place and the edges between them.
let placeCases: [PlaceCase] = [
    // Test 0: Installed in Applications.
    PlaceCase(name: "applications", bundle: "/Applications/Sheepdog.app", quarantined: true, want: .applications),
    // Test 1: Installed in the home Applications folder.
    PlaceCase(name: "home applications", bundle: "/Users/me/Applications/Sheepdog.app", quarantined: true,
              want: .applications),
    // Test 2: Opened from the disk image window.
    PlaceCase(name: "disk image", bundle: "/Volumes/Sheepdog/Sheepdog.app", quarantined: true,
              want: .diskImage(installImage)),
    // Test 3: A disk image volume counts even without quarantine.
    PlaceCase(name: "disk image unquarantined", bundle: "/Volumes/Sheepdog/Sheepdog.app", quarantined: false,
              want: .diskImage(installImage)),
    // Test 4: Opened where the zip unpacked.
    PlaceCase(name: "downloads", bundle: "/Users/me/Downloads/Sheepdog.app", quarantined: true, want: .elsewhere),
    // Test 5: A local build is never asked to move.
    PlaceCase(name: "local build", bundle: "/Users/me/src/sheepdog/.build/Sheepdog.app", quarantined: false,
              want: .applications),
    // Test 6: A volume whose name only starts like the image's is not on the image.
    PlaceCase(name: "similar volume", bundle: "/Volumes/Sheepdog 1/Sheepdog.app", quarantined: true, want: .elsewhere),
    // Test 7: A folder whose name only starts like Applications is not Applications.
    PlaceCase(name: "similar folder", bundle: "/Applications Old/Sheepdog.app", quarantined: true, want: .elsewhere),
    // Test 8: A trailing slash compares the same.
    PlaceCase(name: "trailing slash", bundle: "/Applications/Sheepdog.app/", quarantined: true, want: .applications),
]

// testInstallPlace classifies each bundle path.
@Test(arguments: placeCases)
func testInstallPlace(_ c: PlaceCase) {
    let got = Install.place(bundle: c.bundle, quarantined: c.quarantined, images: [installImage], home: "/Users/me/")
    #expect(got == c.want)
}

// hdiutilInfo is `hdiutil info -plist` output with one mounted image and one attached without a volume.
let hdiutilInfo = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>framework</key><string>683</string>
  <key>images</key>
  <array>
    <dict>
      <key>image-path</key><string>/Users/me/Downloads/sheepdog_macos_universal.dmg</string>
      <key>system-entities</key>
      <array>
        <dict><key>content-hint</key><string>GUID_partition_scheme</string><key>dev-entry</key><string>/dev/disk8</string></dict>
        <dict><key>content-hint</key><string>Apple_HFS</string><key>dev-entry</key><string>/dev/disk8s1</string>
          <key>mount-point</key><string>/Volumes/Sheepdog</string></dict>
      </array>
    </dict>
    <dict>
      <key>image-path</key><string>/Users/me/scratch.sparseimage</string>
      <key>system-entities</key>
      <array><dict><key>dev-entry</key><string>/dev/disk9</string></dict></array>
    </dict>
  </array>
</dict>
</plist>
"""

// testInstallImages reads only images with a mounted volume.
@Test func testInstallImages() {
    #expect(Install.images(hdiutilPlist: Data(hdiutilInfo.utf8)) == [installImage])
    #expect(Install.images(hdiutilPlist: Data("not a plist".utf8)).isEmpty)
    #expect(Install.images(hdiutilPlist: Data()).isEmpty)
}

// testInstallHolding keeps the disk images that carry Sheepdog.app at the top of their volume.
@Test func testInstallHolding() {
    let other = MountedImage(image: "/Users/me/Downloads/Other.dmg", mount: "/Volumes/Other")
    let sparse = MountedImage(image: "/Users/me/work.sparseimage", mount: "/Volumes/Work")
    let present: Set = ["/Volumes/Sheepdog/Sheepdog.app", "/Volumes/Work/Sheepdog.app"]
    let got = Install.holding([installImage, other, sparse]) { present.contains($0) }
    #expect(got == [installImage])
}

// HomebrewCase is one set of existing paths and whether Homebrew should count as the installer.
struct HomebrewCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Present is the set of paths that exist.
    let present: Set<String>
    // Want is the expected result.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// homebrewCases cover neither Caskroom, Apple silicon, and Intel.
let homebrewCases: [HomebrewCase] = [
    // Test 0: No Caskroom folder.
    HomebrewCase(name: "neither", present: [], want: false),
    // Test 1: Apple silicon Caskroom.
    HomebrewCase(name: "apple silicon", present: ["/opt/homebrew/Caskroom/sheepdog"], want: true),
    // Test 2: Intel Caskroom.
    HomebrewCase(name: "intel", present: ["/usr/local/Caskroom/sheepdog"], want: true),
]

// testInstallHomebrew detects a Homebrew install from either Caskroom path.
@Test(arguments: homebrewCases)
func testInstallHomebrew(_ c: HomebrewCase) {
    #expect(Install.homebrew { c.present.contains($0) } == c.want)
}

// KeyCase is one pair of image identities and whether their keys should match.
struct KeyCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // FileA is the file number of the first identity.
    let fileA: UInt64
    // FileB is the file number of the second identity.
    let fileB: UInt64
    // Want reports whether the two keys are expected to be equal.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// keyCases cover the same path with the same and with a different file number.
let keyCases: [KeyCase] = [
    // Test 0: Same path and file number.
    KeyCase(name: "same file", fileA: 7, fileB: 7, want: true),
    // Test 1: Same path, different file number.
    KeyCase(name: "different file number", fileA: 7, fileB: 8, want: false),
]

// testInstallImageKey tells files at one path apart by file number.
@Test(arguments: keyCases)
func testInstallImageKey(_ c: KeyCase) {
    let made = Date(timeIntervalSince1970: 1_700_000_000.9)
    let a = Install.imageKey(path: "/d/a.dmg", fileNumber: c.fileA, created: made)
    let b = Install.imageKey(path: "/d/a.dmg", fileNumber: c.fileB, created: made)
    #expect((a == b) == c.want)
    #expect(a == "/d/a.dmg|\(c.fileA)|1700000000")
}

// PruneCase is a list of keys, the current identities on disk, and the keys that should survive.
struct PruneCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Keys is the stored list.
    let keys: [String]
    // Current maps a path to its present key, absent when the file is gone.
    let current: [String: String]
    // Want is the expected surviving list.
    let want: [String]

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// pruneCases cover a match, a missing file, a changed identity, order, and a path with a separator.
let pruneCases: [PruneCase] = [
    // Test 0: A matching key stays.
    PruneCase(name: "match", keys: ["/a|1|10"], current: ["/a": "/a|1|10"], want: ["/a|1|10"]),
    // Test 1: A key whose file is gone is dropped.
    PruneCase(name: "gone", keys: ["/a|1|10"], current: [:], want: []),
    // Test 2: A key whose identity changed is dropped.
    PruneCase(name: "changed", keys: ["/a|1|10"], current: ["/a": "/a|2|10"], want: []),
    // Test 3: Order is kept.
    PruneCase(name: "order", keys: ["/b|1|1", "/x|1|1", "/a|1|1"],
              current: ["/b": "/b|1|1", "/a": "/a|1|1"], want: ["/b|1|1", "/a|1|1"]),
    // Test 4: A path containing a separator round-trips.
    PruneCase(name: "pipe path", keys: ["/a|b|1|10"], current: ["/a|b": "/a|b|1|10"], want: ["/a|b|1|10"]),
]

// testInstallPruned keeps only keys that still match their file.
@Test(arguments: pruneCases)
func testInstallPruned(_ c: PruneCase) {
    #expect(Install.pruned(c.keys) { c.current[$0] } == c.want)
}

// BrewPathCase is one set of existing paths and the Homebrew executable that should be chosen.
struct BrewPathCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Present is the set of paths that exist.
    let present: Set<String>
    // Want is the expected path, nil when none exists.
    let want: String?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// brewPathCases cover neither, each location alone, and both.
let brewPathCases: [BrewPathCase] = [
    // Test 0: No Homebrew executable.
    BrewPathCase(name: "neither", present: [], want: nil),
    // Test 1: Apple silicon only.
    BrewPathCase(name: "apple silicon", present: ["/opt/homebrew/bin/brew"], want: "/opt/homebrew/bin/brew"),
    // Test 2: Intel only.
    BrewPathCase(name: "intel", present: ["/usr/local/bin/brew"], want: "/usr/local/bin/brew"),
    // Test 3: Both, Apple silicon wins.
    BrewPathCase(name: "both", present: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
                 want: "/opt/homebrew/bin/brew"),
]

// testInstallBrewPath picks the Apple silicon executable before the Intel one.
@Test(arguments: brewPathCases)
func testInstallBrewPath(_ c: BrewPathCase) {
    #expect(Install.brewPath { c.present.contains($0) } == c.want)
}

// DMGCase is one release tag and the download URL it should give.
struct DMGCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Tag is the release tag as given.
    let tag: String
    // Want is the expected URL string.
    let want: String

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// dmgCases cover a tag with and without the v prefix.
let dmgCases: [DMGCase] = [
    // Test 0: A tag with the v prefix.
    DMGCase(name: "v tag", tag: "v1.5.1",
            want: "https://github.com/dcadolph/sheepdog/releases/download/v1.5.1/sheepdog_v1.5.1_macos_universal.dmg"),
    // Test 1: A tag without the v prefix stays without it.
    DMGCase(name: "bare tag", tag: "1.5.1",
            want: "https://github.com/dcadolph/sheepdog/releases/download/1.5.1/sheepdog_1.5.1_macos_universal.dmg"),
]

// testInstallDMGURL builds the download URL from the tag as given.
@Test(arguments: dmgCases)
func testInstallDMGURL(_ c: DMGCase) {
    #expect(Install.dmgURL(tag: c.tag).absoluteString == c.want)
}

// testInstallBrewScript checks the script parses, quotes its values, and quits and reopens the app.
@Test func testInstallBrewScript() throws {
    let script = Install.brewScript(brew: "/opt/homebrew/bin/brew", app: "/Applications/Sheepdog.app")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("sheepdog-\(UUID().uuidString).sh")
    try script.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-n", file.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    #expect(script.hasPrefix("#!/bin/sh\n"))
    #expect(script.contains("/usr/bin/pkill -x Sheepdog"))
    #expect(script.contains("/usr/bin/open '/Applications/Sheepdog.app'"))
    #expect(script.contains("'/opt/homebrew/bin/brew' upgrade --cask sheepdog"))
}

// testInstallBrewScriptQuoting escapes single quotes in interpolated values and still parses.
@Test func testInstallBrewScriptQuoting() throws {
    let script = Install.brewScript(brew: "/b/brew", app: "/Users/o'neil/Sheepdog.app")
    #expect(script.contains("/usr/bin/open '/Users/o'\\''neil/Sheepdog.app'"))
}
