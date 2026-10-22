import Foundation
import Testing

@testable import SheepdogCore

// MergeCase is one dedupe expectation.
struct MergeCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Sources are the per-source entry lists in priority order.
    let sources: [[CalendarEntry]]
    // WantIDs are the event ids kept, in order.
    let wantIDs: [String]

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// mergeEntry returns an entry starting at base plus offset seconds.
func mergeEntry(_ id: String, _ title: String, at offset: TimeInterval = 0, url: String? = nil) -> CalendarEntry {
    CalendarEntry(
        eventID: id,
        title: title,
        start: base.addingTimeInterval(offset),
        end: base.addingTimeInterval(offset + 1800),
        url: url.flatMap(URL.init(string:))
    )
}

// mergeCases covers duplicates with and without links, near misses and empty input.
let mergeCases: [MergeCase] = [
    MergeCase( // Test 0: The Graph copy with a link replaces the EventKit copy without one, in the first slot.
        name: "link wins",
        sources: [
            [mergeEntry("graph:1", "Platform Standup", url: "https://teams.microsoft.com/l/meetup-join/x"), mergeEntry("graph:2", "Later", at: 60)],
            [mergeEntry("ek:1", "  platform   standup ")],
        ],
        wantIDs: ["graph:1", "graph:2"]
    ),
    MergeCase( // Test 1: A later copy with a link replaces an earlier copy without one.
        name: "later link wins",
        sources: [
            [mergeEntry("ek:1", "Standup")],
            [mergeEntry("google:1", "Standup", url: "https://meet.google.com/abc-defg-hij")],
        ],
        wantIDs: ["google:1"]
    ),
    MergeCase( // Test 2: When both have links the first source wins.
        name: "first wins",
        sources: [
            [mergeEntry("graph:1", "Standup", url: "https://zoom.us/j/1")],
            [mergeEntry("google:1", "Standup", url: "https://meet.google.com/abc-defg-hij")],
        ],
        wantIDs: ["graph:1"]
    ),
    MergeCase( // Test 3: When neither has a link the first source wins.
        name: "no links",
        sources: [[mergeEntry("a", "Standup")], [mergeEntry("b", "Standup")]],
        wantIDs: ["a"]
    ),
    MergeCase( // Test 4: Same title at a different start is a different meeting.
        name: "different start",
        sources: [[mergeEntry("a", "Standup")], [mergeEntry("b", "Standup", at: 1)]],
        wantIDs: ["a", "b"]
    ),
    MergeCase( // Test 5: Different titles at the same start are different meetings.
        name: "different title",
        sources: [[mergeEntry("a", "Standup")], [mergeEntry("b", "Standup 2")]],
        wantIDs: ["a", "b"]
    ),
    MergeCase( // Test 6: Nothing in, nothing out.
        name: "empty",
        sources: [[], []],
        wantIDs: []
    ),
]

// testEntryMerge checks dedupe across sources.
@Test(arguments: mergeCases)
func testEntryMerge(test: MergeCase) {
    #expect(EntryMerge.merge(test.sources).map(\.eventID) == test.wantIDs)
}
