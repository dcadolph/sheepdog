import Foundation
import Testing

@testable import Sheepdog
@testable import SheepdogCore

// coordinatorMicStart is the start of the first meeting in the mic cases.
let coordinatorMicStart = Date(timeIntervalSince1970: 2_000_000_000)

// coordinatorMeeting returns a meeting starting the given seconds after coordinatorMicStart.
func coordinatorMeeting(_ id: String, at offset: TimeInterval) -> Meeting {
    let start = coordinatorMicStart.addingTimeInterval(offset)
    return Meeting(id: id, title: "Standup", start: start, end: start.addingTimeInterval(1800))
}

// updateSettings returns settings with the two update switches set as given.
func updateSettings(check: Bool, install: Bool) -> AlertSettings {
    var settings = AlertSettings()
    settings.checkForUpdates = check
    settings.installUpdates = install
    return settings
}

// AllowedCase is one pair of update switches and whether they allow an automatic install.
struct AllowedCase: Sendable, CustomTestStringConvertible {
    // Check is the check-for-updates switch.
    let Check: Bool
    // Install is the install-updates switch.
    let Install: Bool
    // WantAllowed reports whether an automatic install is expected to be allowed.
    let WantAllowed: Bool

    // testDescription labels the case in test output.
    var testDescription: String { "check \(Check) install \(Install)" }
}

// allowedCases cover every combination of the two switches.
let allowedCases: [AllowedCase] = [
    AllowedCase(Check: true, Install: true, WantAllowed: true), // Test 0: Both on allows.
    AllowedCase(Check: true, Install: false, WantAllowed: false), // Test 1: Install off refuses.
    AllowedCase(Check: false, Install: true, WantAllowed: false), // Test 2: Check off refuses.
    AllowedCase(Check: false, Install: false, WantAllowed: false), // Test 3: Both off refuses.
]

// testAutomaticInstallAllowed checks that only both switches on allow an automatic install.
@Test(arguments: allowedCases)
func testAutomaticInstallAllowed(test: AllowedCase) {
    let got = Coordinator.automaticInstallAllowed(updateSettings(check: test.Check, install: test.Install))
    #expect(got == test.WantAllowed)
}

// StagedCase is one staged update at launch and whether it should install.
struct StagedCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let Name: String
    // Tag is the staged release tag.
    var Tag = "v9.9.9"
    // Check is the check-for-updates switch.
    var Check = true
    // Install is the install-updates switch.
    var Install = true
    // Replaceable reports whether the running bundle can be swapped.
    var Replaceable = true
    // Exists reports whether the staged app is still on disk.
    var Exists = true
    // WantInstall reports whether the staged update is expected to install.
    let WantInstall: Bool

    // testDescription labels the case in test output.
    var testDescription: String { Name }
}

// stagedCases run against a running build of 1.17.0.
let stagedCases: [StagedCase] = [
    StagedCase(Name: "good", WantInstall: true), // Test 0: A newer staged update installs.
    StagedCase(Name: "check off", Check: false, WantInstall: false), // Test 1: Check off refuses.
    StagedCase(Name: "install off", Install: false, WantInstall: false), // Test 2: Install off refuses.
    StagedCase(Name: "same version", Tag: "v1.17.0", WantInstall: false), // Test 3: The running tag refuses.
    StagedCase(Name: "bad tag", Tag: "nightly", WantInstall: false), // Test 4: An unparsable tag refuses.
    StagedCase(Name: "not replaceable", Replaceable: false, WantInstall: false), // Test 5: A locked bundle refuses.
    StagedCase(Name: "missing", Exists: false, WantInstall: false), // Test 6: A missing staged app refuses.
]

// testStagedInstallWanted checks which staged updates install at launch.
@Test(arguments: stagedCases)
func testStagedInstallWanted(test: StagedCase) throws {
    let current = try #require(ReleaseVersion("1.17.0"))
    let got = Coordinator.stagedInstallWanted(
        tag: test.Tag, settings: updateSettings(check: test.Check, install: test.Install), current: current,
        replaceable: test.Replaceable, exists: test.Exists)
    #expect(got == test.WantInstall)
}

// testStagedInstallWantedWithoutVersion checks that a build with no known version installs nothing.
@Test func testStagedInstallWantedWithoutVersion() {
    let got = Coordinator.stagedInstallWanted(
        tag: "v9.9.9", settings: updateSettings(check: true, install: true), current: nil, replaceable: true,
        exists: true)
    #expect(!got)
}

// micSettings returns settings with earliestLead 600 and takeoverLead 60.
func micSettings() -> AlertSettings {
    var settings = AlertSettings()
    settings.warningLeads = [600, 300]
    settings.takeoverLead = 60
    return settings
}

// testMicJoinedMarksOne checks that a live mic marks only the meeting at its takeover mark joined.
@Test func testMicJoinedMarksOne() {
    let later = MeetingState(resolution: .skipped)
    let states = ["later": later]
    let got = Coordinator.micJoined(
        meetings: [coordinatorMeeting("now", at: 0), coordinatorMeeting("later", at: 1800)], states: states,
        settings: micSettings(), micRunning: true, micStartedAt: coordinatorMicStart.addingTimeInterval(-180),
        now: coordinatorMicStart.addingTimeInterval(-60))
    #expect(got.joined == "now")
    #expect(got.states == ["now": MeetingState(resolution: .joined), "later": later])
}

// testMicJoinedIdle checks that an idle mic leaves every state untouched.
@Test func testMicJoinedIdle() {
    let states = ["later": MeetingState(resolution: .skipped)]
    let got = Coordinator.micJoined(
        meetings: [coordinatorMeeting("now", at: 0), coordinatorMeeting("later", at: 1800)], states: states,
        settings: micSettings(), micRunning: false, micStartedAt: coordinatorMicStart.addingTimeInterval(-180),
        now: coordinatorMicStart.addingTimeInterval(-60))
    #expect(got.joined == nil)
    #expect(got.states == states)
}
