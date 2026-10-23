import Foundation

// CalendarEntry is a calendar event reduced to the fields Sheepdog needs, independent of EventKit.
public struct CalendarEntry: Sendable, Equatable {
    // ParticipationStatus is the current user's response to an invitation.
    public enum ParticipationStatus: Sendable, Equatable {
        case accepted
        case tentative
        case declined
        case pending
        case unknown
    }

    // EventID is the calendar's identifier for the event, shared by recurring instances.
    public var eventID: String
    // Title is the event title shown to the user.
    public var title: String
    // Start is when the event begins.
    public var start: Date
    // End is when the event ends.
    public var end: Date
    // IsAllDay reports whether the event spans whole days.
    public var isAllDay: Bool
    // IsFree reports whether the event is marked as free time.
    public var isFree: Bool
    // Status is the current user's response, or unknown when the event has no invitation.
    public var status: ParticipationStatus
    // AttendeeCount is the number of attendees other than the current user.
    public var attendeeCount: Int
    // URL is the event's URL field.
    public var url: URL?
    // Location is the event's location text.
    public var location: String?
    // Notes is the event's notes or body text.
    public var notes: String?
    // WebURL is the page that shows the event in its own calendar.
    public var webURL: URL?

    // init creates an entry. Fields not given default to an accepted, busy, timed event.
    public init(
        eventID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        isFree: Bool = false,
        status: ParticipationStatus = .accepted,
        attendeeCount: Int = 1,
        url: URL? = nil,
        location: String? = nil,
        notes: String? = nil,
        webURL: URL? = nil
    ) {
        self.eventID = eventID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isFree = isFree
        self.status = status
        self.attendeeCount = attendeeCount
        self.url = url
        self.location = location
        self.notes = notes
        self.webURL = webURL
    }
}
