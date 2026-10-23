import Foundation

// Meeting is one occurrence of a calendar event that Sheepdog alerts for.
public struct Meeting: Sendable, Equatable, Identifiable {
    // ID identifies this occurrence. Recurring instances differ by start time.
    public var id: String
    // Title is the event title.
    public var title: String
    // Start is when the meeting begins.
    public var start: Date
    // End is when the meeting ends.
    public var end: Date
    // Link is the meeting's join link, when one was found.
    public var link: JoinLink?
    // WebURL is the page that shows the event in its own calendar, when there is one.
    public var webURL: URL?

    // init creates a meeting.
    public init(id: String, title: String, start: Date, end: Date, link: JoinLink? = nil, webURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.link = link
        self.webURL = webURL
    }

    // init converts a calendar entry into a meeting, or returns nil when the entry should never alert.
    public init?(entry: CalendarEntry, settings: AlertSettings) {
        if entry.isAllDay || entry.isFree || entry.status == .declined {
            return nil
        }
        if entry.status == .tentative && !settings.includeTentative {
            return nil
        }
        if settings.requireAttendees && entry.attendeeCount == 0 {
            return nil
        }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: "\(entry.eventID)@\(Int(entry.start.timeIntervalSince1970))",
            title: title.isEmpty ? "Untitled meeting" : title,
            start: entry.start,
            end: entry.end,
            link: JoinLinkFinder.find(in: entry),
            webURL: entry.webURL
        )
    }
}
