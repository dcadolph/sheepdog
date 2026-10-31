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
    // WantStatuses are the kept entries' statuses, in order, checked when not nil.
    var wantStatuses: [CalendarEntry.ParticipationStatus]? = nil

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// mergeEntry returns an entry starting at base plus offset seconds.
func mergeEntry(
    _ id: String, _ title: String, at offset: TimeInterval = 0, url: String? = nil,
    status: CalendarEntry.ParticipationStatus = .accepted
) -> CalendarEntry {
    CalendarEntry(
        eventID: id,
        title: title,
        start: base.addingTimeInterval(offset),
        end: base.addingTimeInterval(offset + 1800),
        status: status,
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
    MergeCase( // Test 2: When both have different links they are two meetings.
        name: "different links",
        sources: [
            [mergeEntry("graph:1", "Standup", url: "https://zoom.us/j/1")],
            [mergeEntry("google:1", "Standup", url: "https://meet.google.com/abc-defg-hij")],
        ],
        wantIDs: ["graph:1", "google:1"]
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
    MergeCase( // Test 7: Two Standups at the same start with different Zoom meetings are both kept.
        name: "different zoom ids",
        sources: [
            [mergeEntry("ek:1", "Standup", url: "https://zoom.us/j/111")],
            [mergeEntry("ek:2", "Standup", url: "https://zoom.us/j/222")],
        ],
        wantIDs: ["ek:1", "ek:2"]
    ),
    MergeCase( // Test 8: The same Teams link with a different query is one meeting.
        name: "same teams link",
        sources: [
            [mergeEntry("graph:1", "Review", url: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=a")],
            [mergeEntry("ek:1", "Review", url: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=b")],
        ],
        wantIDs: ["graph:1"]
    ),
    MergeCase( // Test 9: Graph accepted first outranks an EventKit copy still showing declined.
        name: "direct accepted wins",
        sources: [
            [mergeEntry("graph:1", "Review", status: .accepted)],
            [mergeEntry("ek:1", "Review", status: .declined)],
        ],
        wantIDs: ["graph:1"],
        wantStatuses: [.accepted]
    ),
    MergeCase( // Test 10: Graph declined first silences an EventKit copy showing accepted.
        name: "direct declined wins",
        sources: [
            [mergeEntry("graph:1", "Review", status: .declined)],
            [mergeEntry("ek:1", "Review", status: .accepted)],
        ],
        wantIDs: ["graph:1"],
        wantStatuses: [.declined]
    ),
    MergeCase( // Test 11: An unknown status first takes the next copy's known status.
        name: "unknown takes known",
        sources: [
            [mergeEntry("ek:1", "Review", status: .unknown)],
            [mergeEntry("caldav:1", "Review", status: .accepted)],
        ],
        wantIDs: ["ek:1"],
        wantStatuses: [.accepted]
    ),
]

// testEntryMerge checks dedupe across sources.
@Test(arguments: mergeCases)
func testEntryMerge(test: MergeCase) {
    let got = EntryMerge.merge(test.sources)
    #expect(got.map(\.eventID) == test.wantIDs)
    if let want = test.wantStatuses {
        #expect(got.map(\.status) == want)
    }
}
