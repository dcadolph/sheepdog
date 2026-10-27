import Foundation

// GraphCalendar reads the signed-in user's events from Microsoft Graph.
public enum GraphCalendar {
    // base is the Graph v1.0 root.
    static let base = URL(string: "https://graph.microsoft.com/v1.0")!
    // fields are the event properties requested from calendarView.
    static let fields = [
        "id", "subject", "start", "end", "isAllDay", "isCancelled", "isOrganizer", "showAs",
        "responseStatus", "attendees", "organizer", "onlineMeeting", "onlineMeetingUrl", "location", "body", "webLink",
    ]
    // prefer asks for UTC times and plain text bodies so join links can be found in the body.
    static let prefer = #"outlook.timezone="UTC", outlook.body-content-type="text""#

    // calendarViewRequest asks for every event occurrence that overlaps the window.
    public static func calendarViewRequest(from: Date, to: Date, accessToken: String) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent("me/calendarView"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: from.formatted(.iso8601)),
            URLQueryItem(name: "endDateTime", value: to.formatted(.iso8601)),
            URLQueryItem(name: "$select", value: fields.joined(separator: ",")),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$top", value: "100"),
        ]
        return pageRequest(components.url!, accessToken: accessToken)
    }

    // pageRequest builds a calendarView request for a first or next page.
    static func pageRequest(_ url: URL, accessToken: String) -> URLRequest {
        var request = bearerRequest(url, accessToken: accessToken)
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        return request
    }

    // fetch reads every page of the window and maps the events to entries.
    public static func fetch(
        client: HTTPClient, accessToken: String, from: Date, to: Date, selfAddress: String?
    ) async throws -> [CalendarEntry] {
        var request = calendarViewRequest(from: from, to: to, accessToken: accessToken)
        var entries: [CalendarEntry] = []
        for _ in 0..<maxPages {
            let (data, status) = try await client.send(request)
            try checkStatus(status)
            let page = try decodePage(data)
            entries += page.events.compactMap { entry($0, selfAddress: selfAddress) }
            guard let next = page.next else {
                return entries
            }
            request = pageRequest(next, accessToken: accessToken)
        }
        throw RemoteError.tooManyPages
    }

    // decodePage reads one calendarView page.
    static func decodePage(_ data: Data) throws -> (events: [Event], next: URL?) {
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw RemoteError.decode
        }
        return (page.value, page.nextLink.flatMap(URL.init(string:)))
    }

    // entry maps a Graph event to a CalendarEntry, or returns nil for canceled or unreadable events.
    static func entry(_ event: Event, selfAddress: String?) -> CalendarEntry? {
        if event.isCancelled == true {
            return nil
        }
        guard let start = date(event.start), let end = date(event.end) else {
            return nil
        }
        let me = selfAddress?.lowercased()
        var others = Set(
            (event.attendees ?? [])
                .filter { $0.type != "resource" }
                .compactMap { $0.emailAddress?.address?.lowercased() }
        )
        if event.isOrganizer != true, let organizer = event.organizer?.emailAddress?.address?.lowercased() {
            others.insert(organizer)
        }
        if let me {
            others.remove(me)
        }
        let join = event.onlineMeeting?.joinUrl ?? event.onlineMeetingUrl
        return CalendarEntry(
            eventID: "graph:\(event.id)",
            title: event.subject ?? "",
            start: start,
            end: end,
            isAllDay: event.isAllDay ?? false,
            isFree: event.showAs == "free",
            status: status(event.responseStatus?.response),
            attendeeCount: others.count,
            url: join.flatMap(URL.init(string:)),
            location: event.location?.displayName,
            notes: event.body?.content,
            webURL: event.webLink.flatMap(URL.init(string:))
        )
    }

    // status maps a Graph response value to the core type.
    static func status(_ response: String?) -> CalendarEntry.ParticipationStatus {
        switch response {
        case "accepted", "organizer":
            return .accepted
        case "tentativelyAccepted":
            return .tentative
        case "declined":
            return .declined
        case "notResponded":
            return .pending
        default:
            return .unknown
        }
    }

    // date reads a Graph dateTimeTimeZone, which carries up to seven fractional digits and no offset.
    static func date(_ value: DateTimeZone?) -> Date? {
        guard let value, value.dateTime.count >= 19 else {
            return nil
        }
        let whole = String(value.dateTime.prefix(19))
        guard let utc = try? Date.ISO8601FormatStyle().parse(whole + "Z") else {
            return nil
        }
        guard let zone = TimeZone(identifier: value.timeZone ?? "UTC"), zone.identifier != "UTC" else {
            return utc
        }
        return utc.addingTimeInterval(-TimeInterval(zone.secondsFromGMT(for: utc)))
    }

    // Page is one calendarView response.
    struct Page: Decodable {
        // Value holds the events.
        let value: [Event]
        // NextLink is the URL of the next page, when there is one.
        let nextLink: String?

        // CodingKeys maps the OData field name.
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    // Event is the subset of a Graph event Sheepdog reads.
    struct Event: Decodable {
        // ID is the occurrence id.
        let id: String
        // Subject is the title.
        let subject: String?
        // Start is when the event begins.
        let start: DateTimeZone?
        // End is when the event ends.
        let end: DateTimeZone?
        // IsAllDay reports an all-day event.
        let isAllDay: Bool?
        // IsCancelled reports an event the organizer canceled.
        let isCancelled: Bool?
        // IsOrganizer reports whether the user organized the event.
        let isOrganizer: Bool?
        // ShowAs is the free/busy value, such as free or busy.
        let showAs: String?
        // ResponseStatus is the user's response.
        let responseStatus: ResponseStatus?
        // Attendees are the invitees.
        let attendees: [Attendee]?
        // Organizer is who sent the invitation.
        let organizer: Recipient?
        // OnlineMeeting carries the Teams join link.
        let onlineMeeting: OnlineMeeting?
        // OnlineMeetingURL is the older join link field.
        let onlineMeetingUrl: String?
        // Location is where the event happens.
        let location: Location?
        // Body is the event description.
        let body: Body?
        // WebLink is the event's page in Outlook on the web.
        let webLink: String?
    }

    // DateTimeZone is a wall time and the zone it is in.
    struct DateTimeZone: Decodable {
        // DateTime is the wall time without an offset.
        let dateTime: String
        // TimeZone is the zone name, UTC when requested.
        let timeZone: String?
    }

    // ResponseStatus is the user's response to an event.
    struct ResponseStatus: Decodable {
        // Response is the response value.
        let response: String?
    }

    // Attendee is one invitee.
    struct Attendee: Decodable {
        // Type is required, optional or resource.
        let type: String?
        // EmailAddress identifies the invitee.
        let emailAddress: EmailAddress?
    }

    // Recipient wraps an address.
    struct Recipient: Decodable {
        // EmailAddress identifies the recipient.
        let emailAddress: EmailAddress?
    }

    // EmailAddress is a name and address.
    struct EmailAddress: Decodable {
        // Address is the mail address.
        let address: String?
    }

    // OnlineMeeting holds online meeting details.
    struct OnlineMeeting: Decodable {
        // JoinURL is the link that joins the meeting.
        let joinUrl: String?
    }

    // Location is an event location.
    struct Location: Decodable {
        // DisplayName is the location text.
        let displayName: String?
    }

    // Body is an event description.
    struct Body: Decodable {
        // Content is the description text.
        let content: String?
    }
}
