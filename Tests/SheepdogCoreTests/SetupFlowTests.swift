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
