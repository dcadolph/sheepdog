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

// NotarizedCase is one spctl output and whether it counts as notarized.
struct NotarizedCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Output is the spctl output.
    let output: String
    // Want reports whether the output counts as notarized.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// notarizedCases cover accepted output with and without the notarized source line.
let notarizedCases: [NotarizedCase] = [
    NotarizedCase(name: "notarized", output: "/x/Sheepdog.app: accepted\nsource=Notarized Developer ID\n", want: true), // Test 0: Both lines.
    NotarizedCase(name: "no source", output: "/x/Sheepdog.app: accepted\n", want: false), // Test 1: Accepted alone.
    NotarizedCase(name: "other source", output: "/x/Sheepdog.app: accepted\nsource=Developer ID\n", want: false), // Test 2: Not notarized.
    NotarizedCase(name: "rejected", output: "/x/Sheepdog.app: rejected\nsource=Notarized Developer ID\n", want: false), // Test 3: Rejected.
    NotarizedCase(name: "empty", output: "", want: false), // Test 4: Empty.
]

// testInstallNotarized checks which spctl output counts as notarized.
@Test(arguments: notarizedCases)
func testInstallNotarized(test: NotarizedCase) {
    #expect(Install.notarized(test.output) == test.want)
}

// RunsCase is one minimum version text and whether a bundle needing it runs on macOS 14.6.1.
struct RunsCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Minimum is the bundle's minimum system version, or nil when it names none.
    let minimum: String?
    // Want reports whether the bundle runs.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// runsCases cover missing, older, equal, newer and unreadable minimums.
let runsCases: [RunsCase] = [
    RunsCase(name: "nil", minimum: nil, want: true), // Test 0: No minimum.
    RunsCase(name: "15", minimum: "15", want: false), // Test 1: Newer major.
    RunsCase(name: "14.0", minimum: "14.0", want: true), // Test 2: Older minor.
    RunsCase(name: "14.6.1", minimum: "14.6.1", want: true), // Test 3: Equal.
    RunsCase(name: "14.6.2", minimum: "14.6.2", want: false), // Test 4: Newer patch.
    RunsCase(name: "junk", minimum: "junk", want: false), // Test 5: Words.
    RunsCase(name: "empty", minimum: "", want: false), // Test 6: Empty.
    RunsCase(name: "four parts", minimum: "14.0.0.1", want: false), // Test 7: Too many parts.
]

// testInstallRuns checks the minimum system version rule on macOS 14.6.1.
@Test(arguments: runsCases)
func testInstallRuns(test: RunsCase) {
    let os = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1)
    #expect(Install.runs(minimum: test.minimum, on: os) == test.want)
}

#if os(macOS)
// testInstallSigned accepts code that meets a requirement and refuses what the release requirement
// rules out: an Apple app, an ad hoc signed copy, and a missing path.
@Test func testInstallSigned() throws {
    #expect(Install.signed("/System/Applications/Calculator.app", requirement: "anchor apple"))
    #expect(!Install.signed("/System/Applications/Calculator.app", requirement: Install.releaseRequirement))
    #expect(!Install.signed("/nonexistent/Sheepdog.app", requirement: "anchor apple"))
    #expect(!Install.signed("/System/Applications/Calculator.app", requirement: "not a requirement ("))

    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("sheepdog-adhoc-\(UUID().uuidString)")
    try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: copy.path)
    defer { try? FileManager.default.removeItem(at: copy) }
    let sign = Process()
    sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    sign.arguments = ["--force", "--sign", "-", "--identifier", "com.dcadolph.sheepdog", copy.path]
    sign.standardError = FileHandle.nullDevice
    try sign.run()
    sign.waitUntilExit()
    #expect(sign.terminationStatus == 0)
    #expect(Install.signed(copy.path, requirement: "identifier \"com.dcadolph.sheepdog\""))
    #expect(!Install.signed(copy.path, requirement: Install.releaseRequirement))
}
#endif
