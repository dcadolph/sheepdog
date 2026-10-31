import Foundation
import Testing

@testable import Sheepdog
@testable import SheepdogCore

// testSession is an account whose read waits until the test finishes it.
actor testSession: AccountSession {
    // record is the stored account.
    nonisolated let record = AccountRecord(
        kind: .caldav, address: "test@example.com",
        credential: .password(server: URL(fileURLWithPath: "/"), username: "test", password: "test"))
    // waiting is the read in progress, nil when none.
    private var waiting: CheckedContinuation<[CalendarEntry], Never>?

    // isWaiting reports whether a read is in progress.
    var isWaiting: Bool { waiting != nil }

    // entries waits for finish and returns what it was given.
    func entries(from: Date, to: Date) async throws -> [CalendarEntry] {
        await withCheckedContinuation { waiting = $0 }
    }

    // finish ends the read in progress with entries.
    func finish(_ entries: [CalendarEntry]) {
        waiting?.resume(returning: entries)
        waiting = nil
    }
}

// AccountsRaceCase is one read and whether the account is disconnected while it waits.
struct AccountsRaceCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let Name: String
    // Disconnect reports whether the account is disconnected during the read.
    let Disconnect: Bool
    // WantCount is how many services hold cached events after the read.
    let WantCount: Int
    // WantState is the account's state after the read.
    let WantState: AccountState

    // testDescription labels the case in test output.
    var testDescription: String { Name }
}

// accountsRaceCases cover a read that outlives its account and one that does not.
let accountsRaceCases: [AccountsRaceCase] = [
    AccountsRaceCase( // Test 0: A disconnect during the read drops what it returns.
        Name: "disconnected", Disconnect: true, WantCount: 0, WantState: .signedOut
    ),
    AccountsRaceCase( // Test 1: A read with no disconnect is kept.
        Name: "kept", Disconnect: false, WantCount: 1, WantState: .connected("test@example.com")
    ),
]

// testAccountsRefreshDropsStaleRead checks that a read finishing after a disconnect never revives the
// account or its events.
@MainActor
@Test(arguments: accountsRaceCases)
func testAccountsRefreshDropsStaleRead(test: AccountsRaceCase) async throws {
    let accounts = Accounts(fixture: [.caldav: .signedOut])
    let session = testSession()
    accounts.attachForTesting(session, kind: .caldav)
    accounts.refresh(force: true)
    while await !session.isWaiting {
        await Task.yield()
    }
    if test.Disconnect {
        accounts.disconnect(.caldav)
    }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = CalendarEntry(eventID: "1", title: "Standup", start: start, end: start.addingTimeInterval(900))
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        accounts.onChange = { done.resume() }
        Task { await session.finish([entry]) }
    }
    #expect(accounts.entries.count == test.WantCount)
    #expect(accounts.states[.caldav] == test.WantState)
}
