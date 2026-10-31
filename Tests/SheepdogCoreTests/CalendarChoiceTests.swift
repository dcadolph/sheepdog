import Foundation
import Testing

@testable import SheepdogCore

// AllowedCase is one hidden list and the calendars left to read.
struct AllowedCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let Name: String
    // All are the calendar ids in store order.
    let All: [String]
    // Hidden are the unchecked ids.
    let Hidden: Set<String>
    // WantIDs are the ids read, in order.
    let WantIDs: [String]

    // testDescription labels the case in test output.
    var testDescription: String { Name }
}

// allowedCases cover filtering, order, and the empty and full hidden lists.
let allowedCases: [AllowedCase] = [
    AllowedCase( // Test 0: Hidden ids are left out and the rest keep their order.
        Name: "filters", All: ["c", "a", "b"], Hidden: ["a"], WantIDs: ["c", "b"]
    ),
    AllowedCase( // Test 1: Nothing hidden reads every calendar.
        Name: "none hidden", All: ["a", "b"], Hidden: [], WantIDs: ["a", "b"]
    ),
    AllowedCase( // Test 2: Every calendar hidden reads none.
        Name: "all hidden", All: ["a", "b"], Hidden: ["a", "b"], WantIDs: []
    ),
    AllowedCase( // Test 3: An id from another Mac changes nothing.
        Name: "unknown id", All: ["a"], Hidden: ["z"], WantIDs: ["a"]
    ),
]

// testCalendarChoiceAllowed checks which calendars are read.
@Test(arguments: allowedCases)
func testCalendarChoiceAllowed(test: AllowedCase) {
    #expect(CalendarChoice.allowed(all: test.All, hidden: test.Hidden) == test.WantIDs)
}

// SummaryCase is one source count and its wording.
struct SummaryCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let Name: String
    // Total is the source's calendar count.
    let Total: Int
    // Hidden is how many are unchecked.
    let Hidden: Int
    // WantResult is the wording.
    let WantResult: String

    // testDescription labels the case in test output.
    var testDescription: String { Name }
}

// summaryCases cover the plain count, the partial count and singulars.
let summaryCases: [SummaryCase] = [
    SummaryCase(Name: "all", Total: 5, Hidden: 0, WantResult: "5 calendars"), // Test 0: All read.
    SummaryCase(Name: "some", Total: 5, Hidden: 2, WantResult: "3 of 5 calendars"), // Test 1: Some hidden.
    SummaryCase(Name: "one", Total: 1, Hidden: 0, WantResult: "1 calendar"), // Test 2: Singular.
    SummaryCase(Name: "one hidden", Total: 1, Hidden: 1, WantResult: "0 of 1 calendar"), // Test 3: Only one, hidden.
    SummaryCase(Name: "overcount", Total: 2, Hidden: 3, WantResult: "0 of 2 calendars"), // Test 4: Clamped.
]

// testCalendarChoiceSummary checks the source row wording.
@Test(arguments: summaryCases)
func testCalendarChoiceSummary(test: SummaryCase) {
    #expect(CalendarChoice.summary(total: test.Total, hidden: test.Hidden) == test.WantResult)
}
