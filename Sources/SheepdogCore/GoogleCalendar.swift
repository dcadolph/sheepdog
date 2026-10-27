import Foundation

// GoogleCalendar reads the signed-in user's events from the Google Calendar API.
public enum GoogleCalendar {
    // base is the Calendar API v3 root.
    static let base = "https://www.googleapis.com/calendar/v3"
    // skippedTypes are event types that are never meetings.
    static let skippedTypes: Set<String> = ["workingLocation", "outOfOffice", "birthday"]

    // calendarListRequest asks for one page of the user's calendar list.
    public static func calendarListRequest(accessToken: String, pageToken: String?) -> URLRequest {
        var components = URLComponents(string: "\(base)/users/me/calendarList")!
        components.queryItems = [URLQueryItem(name: "minAccessRole", value: "reader")]
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return bearerRequest(components.url!, accessToken: accessToken)
    }

    // eventsRequest asks for one page of a calendar's event occurrences that overlap the window.
    public static func eventsRequest(
        calendarID: String, from: Date, to: Date, accessToken: String, pageToken: String?
    ) -> URLRequest {
        var components = URLComponents(string: "\(base)/calendars/\(percentEncode(calendarID))/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: from.formatted(.iso8601)),
            URLQueryItem(name: "timeMax", value: to.formatted(.iso8601)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return bearerRequest(components.url!, accessToken: accessToken)
    }

    // fetch reads every calendar the user owns and maps its events in the window to entries.
    public static func fetch(client: HTTPClient, accessToken: String, from: Date, to: Date) async throws -> [CalendarEntry] {
        var entries: [CalendarEntry] = []
        for calendar in try await calendars(client: client, accessToken: accessToken) {
            var pageToken: String?
            var done = false
            for _ in 0..<maxPages {
                let request = eventsRequest(
                    calendarID: calendar.id, from: from, to: to, accessToken: accessToken, pageToken: pageToken
                )
                let (data, status) = try await client.send(request)
                try checkStatus(status)
                let page = try decode(EventPage.self, from: data)
                entries += page.items.compactMap(entry)
                pageToken = page.nextPageToken
                if pageToken == nil {
                    done = true
                    break
                }
            }
            if !done {
                throw RemoteError.tooManyPages
            }
        }
        return entries
    }

    // profile returns the account's address, the id of the primary calendar list entry.
    // It reads the calendar list rather than calendars/primary, so the calendarlist.readonly scope is enough.
    public static func profile(client: HTTPClient, accessToken: String) async throws -> String? {
        try await list(client: client, accessToken: accessToken).first { $0.primary == true }?.id
    }

    // calendars returns the calendars whose events are the user's own meetings.
    static func calendars(client: HTTPClient, accessToken: String) async throws -> [Calendar] {
        owned(try await list(client: client, accessToken: accessToken))
    }

    // list returns every entry in the user's calendar list.
    static func list(client: HTTPClient, accessToken: String) async throws -> [Calendar] {
        var all: [Calendar] = []
        var pageToken: String?
        for _ in 0..<maxPages {
            let (data, status) = try await client.send(calendarListRequest(accessToken: accessToken, pageToken: pageToken))
            try checkStatus(status)
            let page = try decode(CalendarPage.self, from: data)
            all += page.items
            pageToken = page.nextPageToken
            if pageToken == nil {
                return all
            }
        }
        throw RemoteError.tooManyPages
    }

    // owned keeps the primary calendar and any other calendar the user owns and shows.
    // Calendars shared by other people are left out, because their events are not the user's meetings.
    static func owned(_ calendars: [Calendar]) -> [Calendar] {
        calendars.filter { calendar in
            if calendar.deleted == true {
                return false
            }
            if calendar.primary == true {
                return true
            }
            return calendar.accessRole == "owner" && calendar.selected == true
        }
    }

    // entry maps a Google event to a CalendarEntry, or returns nil for canceled and non-meeting events.
    static func entry(_ event: Event) -> CalendarEntry? {
        if event.status == "cancelled" || skippedTypes.contains(event.eventType ?? "") {
            return nil
        }
        guard let start = date(event.start), let end = date(event.end) else {
            return nil
        }
        let attendees = event.attendees ?? []
        let me = attendees.first { $0.isSelf == true }
        let others = attendees.filter { $0.isSelf != true && $0.resource != true }
        let video = event.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
        return CalendarEntry(
            eventID: "google:\(event.id)",
            title: event.summary ?? "",
            start: start,
            end: end,
            isAllDay: event.start?.date != nil,
            isFree: event.transparency == "transparent",
            status: me.map { status($0.responseStatus) } ?? (event.organizer?.isSelf == true ? .accepted : .unknown),
            attendeeCount: others.count,
            url: (event.hangoutLink ?? video).flatMap(URL.init(string:)),
            location: event.location,
            notes: event.description,
            webURL: event.htmlLink.flatMap(URL.init(string:))
        )
    }

    // status maps a Google responseStatus to the core type.
    static func status(_ response: String?) -> CalendarEntry.ParticipationStatus {
        switch response {
        case "accepted":
            return .accepted
        case "tentative":
            return .tentative
        case "declined":
            return .declined
        case "needsAction":
            return .pending
        default:
            return .unknown
        }
    }

    // date reads an RFC 3339 dateTime, or a whole date taken as midnight UTC.
    static func date(_ value: EventTime?) -> Date? {
        if let dateTime = value?.dateTime {
            return (try? Date.ISO8601FormatStyle().parse(dateTime))
                ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(dateTime))
        }
        if let day = value?.date {
            return try? Date.ISO8601FormatStyle().parse(day + "T00:00:00Z")
        }
        return nil
    }

    // decode reads a JSON body or throws RemoteError.decode.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw RemoteError.decode
        }
        return value
    }

    // CalendarPage is one calendarList response.
    struct CalendarPage: Decodable {
        // Items are the calendars.
        let items: [Calendar]
        // NextPageToken requests the next page, when there is one.
        let nextPageToken: String?
    }

    // Calendar is the subset of a calendar list entry Sheepdog reads.
    struct Calendar: Decodable {
        // ID is the calendar id. The primary calendar's id is the account's address.
        let id: String
        // Primary reports the user's main calendar.
        let primary: Bool?
        // AccessRole is the user's role, such as owner or reader.
        let accessRole: String?
        // Selected reports whether the calendar is shown in the Google Calendar UI.
        let selected: Bool?
        // Deleted reports a calendar removed from the list.
        let deleted: Bool?
    }

    // EventPage is one events response.
    struct EventPage: Decodable {
        // Items are the event occurrences.
        let items: [Event]
        // NextPageToken requests the next page, when there is one.
        let nextPageToken: String?
    }

    // Event is the subset of a Google event Sheepdog reads.
    struct Event: Decodable {
        // ID is the occurrence id.
        let id: String
        // Status is confirmed, tentative or cancelled.
        let status: String?
        // Summary is the title.
        let summary: String?
        // Start is when the event begins.
        let start: EventTime?
        // End is when the event ends.
        let end: EventTime?
        // Transparency is transparent when the event does not block time.
        let transparency: String?
        // EventType is default, focusTime, outOfOffice, workingLocation and others.
        let eventType: String?
        // Attendees are the invitees, including the user.
        let attendees: [Attendee]?
        // Organizer is who created the meeting.
        let organizer: Person?
        // HangoutLink is the Google Meet link.
        let hangoutLink: String?
        // ConferenceData holds links from conferencing add-ons such as Zoom.
        let conferenceData: ConferenceData?
        // Location is the location text.
        let location: String?
        // Description is the event description.
        let description: String?
        // HTMLLink is the event's page in Google Calendar.
        let htmlLink: String?
    }

    // EventTime is either a dateTime with an offset or a whole date.
    struct EventTime: Decodable {
        // DateTime is the RFC 3339 time for timed events.
        let dateTime: String?
        // Date is the day for all-day events.
        let date: String?
    }

    // Attendee is one invitee.
    struct Attendee: Decodable {
        // IsSelf reports whether this attendee is the user.
        let isSelf: Bool?
        // Resource reports a room or other resource.
        let resource: Bool?
        // ResponseStatus is needsAction, declined, tentative or accepted.
        let responseStatus: String?

        // CodingKeys maps the reserved field name self.
        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case resource
            case responseStatus
        }
    }

    // Person is an organizer or creator.
    struct Person: Decodable {
        // IsSelf reports whether this person is the user.
        let isSelf: Bool?

        // CodingKeys maps the reserved field name self.
        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
        }
    }

    // ConferenceData holds conference entry points.
    struct ConferenceData: Decodable {
        // EntryPoints are the ways to join.
        let entryPoints: [EntryPoint]?
    }

    // EntryPoint is one way to join a conference.
    struct EntryPoint: Decodable {
        // EntryPointType is video, phone, sip or more.
        let entryPointType: String?
        // URI is the join address.
        let uri: String?
    }
}
