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
