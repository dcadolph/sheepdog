import Foundation
import Testing

@testable import SheepdogCore

// setupDone is a record of a finished flow.
let setupDone = SetupFlowRecord(completed: Date(timeIntervalSince1970: 1_800_000_000), version: "1.13.0")
// setupUnfinished is a record whose flow was never finished.
let setupUnfinished = SetupFlowRecord(completed: nil, version: "1.13.0")
// setupAll is every step in order.
let setupAll: [SetupStep] = [.access, .connect, .bark, .dressUp, .done]

// SetupFlowCase is one launch state and the steps it should show.
struct SetupFlowCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Fresh is true when no settings are stored.
    let fresh: Bool
    // Record is the stored setup record, if any.
    let record: SetupFlowRecord?
    // Want is the steps to show.
    let want: [SetupStep]

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// setupFlowCases cover fresh installs, upgrades, and completed or unfinished records.
let setupFlowCases: [SetupFlowCase] = [
    SetupFlowCase(name: "fresh no record", fresh: true, record: nil, want: setupAll), // Test 0: All five.
    SetupFlowCase(name: "upgrade no record", fresh: false, record: nil, want: [.dressUp, .done]), // Test 1: Upgrade.
    SetupFlowCase(name: "fresh completed", fresh: true, record: setupDone, want: []), // Test 2: Done.
    SetupFlowCase(name: "upgrade completed", fresh: false, record: setupDone, want: []), // Test 3: Done.
    SetupFlowCase(name: "fresh unfinished", fresh: true, record: setupUnfinished, want: setupAll), // Test 4: Like none.
    SetupFlowCase(name: "upgrade unfinished", fresh: false, record: setupUnfinished, want: [.dressUp, .done]), // Test 5: Like none.
]

// testSetupSteps checks which steps each launch state shows.
@Test(arguments: setupFlowCases)
func testSetupSteps(test: SetupFlowCase) {
    #expect(SetupFlow.steps(fresh: test.fresh, record: test.record) == test.want)
}

// SetupReopenCase is one access state and the steps a reopen should show.
struct SetupReopenCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Granted is true when calendar access is granted.
    let granted: Bool
    // UsesMac is true when macOS Calendar is in use.
    let usesMac: Bool
    // Want is the steps to show.
    let want: [SetupStep]

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// setupReopenCases cover granted, unused, and denied access.
let setupReopenCases: [SetupReopenCase] = [
    SetupReopenCase(name: "granted", granted: true, usesMac: true, want: [.connect, .bark, .dressUp, .done]), // Test 0: Four.
    SetupReopenCase(name: "mac calendar off", granted: false, usesMac: false, want: [.connect, .bark, .dressUp, .done]), // Test 1: Four.
    SetupReopenCase(name: "denied", granted: false, usesMac: true, want: setupAll), // Test 2: Five.
]

// testSetupReopen checks the steps shown when setup is reopened.
@Test(arguments: setupReopenCases)
func testSetupReopen(test: SetupReopenCase) {
    let got = SetupFlow.reopenSteps(accessGranted: test.granted, usesMacCalendar: test.usesMac)
    #expect(got == test.want)
}

// SetupLoginCase is one login item state and the Done step's starting choice.
struct SetupLoginCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Fresh is true when no settings were stored at launch.
    let fresh: Bool
    // Configured is true when the login choice was already made on this Mac.
    let configured: Bool
    // Enabled is true when the login item is registered.
    let enabled: Bool
    // NeedsApproval is true when macOS waits on the user to approve the login item.
    let needsApproval: Bool
    // Want is the starting choice.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// setupLoginCases cover a first run, a reopen after either choice, and upgrades.
let setupLoginCases: [SetupLoginCase] = [
    SetupLoginCase(name: "fresh first run", fresh: true, configured: false, enabled: false, needsApproval: false, want: true), // Test 0: On.
    SetupLoginCase(name: "fresh reopen after off", fresh: true, configured: true, enabled: false, needsApproval: false, want: false), // Test 1: Keeps off.
    SetupLoginCase(name: "fresh reopen after on", fresh: true, configured: true, enabled: true, needsApproval: false, want: true), // Test 2: Keeps on.
    SetupLoginCase(name: "fresh reopen pending", fresh: true, configured: true, enabled: false, needsApproval: true, want: true), // Test 3: Pending.
    SetupLoginCase(name: "upgrade off", fresh: false, configured: true, enabled: false, needsApproval: false, want: false), // Test 4: Off.
    SetupLoginCase(name: "upgrade on", fresh: false, configured: true, enabled: true, needsApproval: false, want: true), // Test 5: On.
]

// testSetupStartsAtLogin checks the Done step's starting login choice.
@Test(arguments: setupLoginCases)
func testSetupStartsAtLogin(test: SetupLoginCase) {
    let got = SetupFlow.startsAtLogin(
        fresh: test.fresh, configured: test.configured, enabled: test.enabled, needsApproval: test.needsApproval
    )
    #expect(got == test.want)
}

// SetupHolidaysCase is one launch state and whether it switches holiday outfits and tunes off.
struct SetupHolidaysCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Fresh is true when no settings are stored.
    let fresh: Bool
    // Record is the stored setup record, if any.
    let record: SetupFlowRecord?
    // Want is true when the launch switches them off.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// setupHolidaysCases cover fresh installs, upgrades, and completed or unfinished records.
let setupHolidaysCases: [SetupHolidaysCase] = [
    SetupHolidaysCase(name: "fresh no record", fresh: true, record: nil, want: false), // Test 0: Already off.
    SetupHolidaysCase(name: "upgrade no record", fresh: false, record: nil, want: true), // Test 1: Once.
    SetupHolidaysCase(name: "fresh completed", fresh: true, record: setupDone, want: false), // Test 2: Done.
    SetupHolidaysCase(name: "upgrade completed", fresh: false, record: setupDone, want: false), // Test 3: Keeps choice.
    SetupHolidaysCase(name: "fresh unfinished", fresh: true, record: setupUnfinished, want: false), // Test 4: Fresh.
    SetupHolidaysCase(name: "upgrade unfinished", fresh: false, record: setupUnfinished, want: true), // Test 5: Like none.
]

// testSetupResetsHolidays checks which launches switch holiday outfits and tunes off.
@Test(arguments: setupHolidaysCases)
func testSetupResetsHolidays(test: SetupHolidaysCase) {
    #expect(SetupFlow.resetsHolidays(fresh: test.fresh, record: test.record) == test.want)
}

// testSetupTitles checks the heading of every step.
@Test
func testSetupTitles() {
    let titles = SetupStep.allCases.map(\.title)
    #expect(titles == ["Welcome", "Connect calendars", "When should Tug bark?", "Tug dresses up", "Done"])
}

// testSetupRecordRoundTrip checks the record survives encoding.
@Test
func testSetupRecordRoundTrip() throws {
    let data = try JSONEncoder().encode(setupDone)
    #expect(try JSONDecoder().decode(SetupFlowRecord.self, from: data) == setupDone)
}
