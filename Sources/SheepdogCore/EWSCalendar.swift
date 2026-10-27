import Foundation

// EWSCalendar reads events from an Exchange server over Exchange Web Services, with FindItem and GetItem
// only. The server expands recurring events, so the client never does recurrence math. Credentials are not
// part of the requests: the client answers the server's Basic or NTLM challenge.
public enum EWSCalendar {
    // soap is the SOAP 1.1 envelope namespace.
    static let soap = "http://schemas.xmlsoap.org/soap/envelope/"
    // messages is the EWS messages namespace.
    static let messages = "http://schemas.microsoft.com/exchange/services/2006/messages"
    // types is the EWS types namespace.
    static let types = "http://schemas.microsoft.com/exchange/services/2006/types"
    // serverVersion is the oldest schema that has JoinOnlineMeetingUrl.
    static let serverVersion = "Exchange2013"
    // pageSize is how many occurrences one FindItem asks for before paging on.
    static let pageSize = 200
    // batchSize is how many items one GetItem asks for.
    static let batchSize = 20
    // fields are the calendar item properties GetItem asks for.
    static let fields = [
        "item:Subject", "item:Body", "item:WebClientReadFormQueryString", "calendar:UID", "calendar:Start",
        "calendar:End", "calendar:IsAllDayEvent", "calendar:IsCancelled", "calendar:LegacyFreeBusyStatus",
        "calendar:MyResponseType", "calendar:Location", "calendar:Organizer", "calendar:RequiredAttendees",
        "calendar:OptionalAttendees", "calendar:JoinOnlineMeetingUrl",
    ]

    // Page is one FindItem reply: the occurrences in order and whether the view reached the end of the window.
    struct Page: Equatable {
        // Items are the occurrence ids with their start times.
        let items: [(id: String, start: Date?)]
        // Complete reports that the server returned the last occurrence in the window.
        let complete: Bool

        // == compares pages by ids, starts and completeness.
        static func == (lhs: Page, rhs: Page) -> Bool {
            lhs.complete == rhs.complete && lhs.items.map(\.id) == rhs.items.map(\.id)
                && lhs.items.map(\.start) == rhs.items.map(\.start)
        }
    }

    // findItemRequest asks the calendar folder for every occurrence that overlaps the window.
    public static func findItemRequest(server: URL, from: Date, to: Date) -> URLRequest {
        let view = #"MaxEntriesReturned="\#(pageSize)" StartDate="\#(stamp(from))" EndDate="\#(stamp(to))""#
        return soapRequest(server, body: """
        <m:FindItem Traversal="Shallow">
        <m:ItemShape><t:BaseShape>IdOnly</t:BaseShape><t:AdditionalProperties>\
        <t:FieldURI FieldURI="calendar:Start"/></t:AdditionalProperties></m:ItemShape>
        <m:CalendarView \(view)/>
        <m:ParentFolderIds><t:DistinguishedFolderId Id="calendar"/></m:ParentFolderIds>
        </m:FindItem>
        """)
    }

    // getItemRequest asks for the properties Sheepdog needs of each item, with the body as plain text.
    public static func getItemRequest(server: URL, ids: [String]) -> URLRequest {
        let props = fields.map { #"<t:FieldURI FieldURI="\#($0)"/>"# }.joined()
        let list = ids.map { #"<t:ItemId Id="\#(escape($0))"/>"# }.joined()
        return soapRequest(server, body: """
        <m:GetItem>
        <m:ItemShape><t:BaseShape>IdOnly</t:BaseShape><t:BodyType>Text</t:BodyType>\
        <t:AdditionalProperties>\(props)</t:AdditionalProperties></m:ItemShape>
        <m:ItemIds>\(list)</m:ItemIds>
        </m:GetItem>
        """)
    }

    // fetch reads every occurrence in the window and maps it to an entry. Addresses are the user's own mail
    // addresses, used to leave the user out of the attendee count.
    public static func fetch(
        client: HTTPClient, server: URL, addresses: [String], from: Date, to: Date, floating: TimeZone = .current
    ) async throws -> [CalendarEntry] {
        let ids = try await occurrences(client: client, server: server, from: from, to: to)
        let mine = Set(addresses.map { $0.lowercased() })
        var entries: [CalendarEntry] = []
        for start in stride(from: 0, to: ids.count, by: batchSize) {
            let batch = Array(ids[start..<min(start + batchSize, ids.count)])
            let (data, status) = try await client.send(getItemRequest(server: server, ids: batch))
            try checkStatus(status)
            entries += try items(data).compactMap { entry($0, addresses: mine, floating: floating) }
        }
        return entries.filter { $0.end > from && $0.start < to }
    }

    // occurrences pages through the calendar view and returns each occurrence id once, in order. A full page
    // moves the view's start to the last occurrence's start, and a page that cannot move it is an error.
    static func occurrences(client: HTTPClient, server: URL, from: Date, to: Date) async throws -> [String] {
        var ids: [String] = []
        var seen: Set<String> = []
        var start = from
        for _ in 0..<maxPages {
            let (data, status) = try await client.send(findItemRequest(server: server, from: start, to: to))
            try checkStatus(status)
            let page = try findItemPage(data)
            for item in page.items where seen.insert(item.id).inserted {
                ids.append(item.id)
            }
            if page.complete {
                return ids
            }
            guard let last = page.items.last?.start, last > start else {
                throw RemoteError.tooManyPages
            }
            start = last
        }
        throw RemoteError.tooManyPages
    }

    // findItemPage reads a FindItem reply.
    static func findItemPage(_ data: Data) throws -> Page {
        let message = try responseMessages(data, "FindItemResponse").first
        guard let message else {
            throw RemoteError.decode
        }
        try checkMessage(message)
        guard let root = message.child(messages, "RootFolder") else {
            throw RemoteError.decode
        }
        let items = (root.child(types, "Items")?.children ?? []).compactMap { item -> (id: String, start: Date?)? in
            guard let id = item.child(types, "ItemId")?.attributes["Id"], !id.isEmpty else {
                return nil
            }
            return (id, item.child(types, "Start").flatMap { date($0.trimmedText) })
        }
        let complete = root.attributes["IncludesLastItemInRange"]?.lowercased() != "false"
        return Page(items: items, complete: complete)
    }

    // items reads a GetItem reply, skipping items the server could not return, such as one deleted since FindItem.
    static func items(_ data: Data) throws -> [CalDAVCalendar.DAVNode] {
        try responseMessages(data, "GetItemResponse").flatMap { message -> [CalDAVCalendar.DAVNode] in
            if message.attributes["ResponseClass"] == "Error" {
                return []
            }
            return message.child(messages, "Items")?.children(types, "CalendarItem") ?? []
        }
    }

    // responseMessages returns the messages of a SOAP reply, throwing for a fault or a body of another kind.
    static func responseMessages(_ data: Data, _ name: String) throws -> [CalDAVCalendar.DAVNode] {
        guard let envelope = CalDAVCalendar.XMLTree.parse(data), envelope.namespace == soap,
              envelope.name == "Envelope", let body = envelope.child(soap, "Body")
        else {
            throw RemoteError.decode
        }
        if body.child(soap, "Fault") != nil {
            throw RemoteError.server(status: 500)
        }
        guard let response = body.child(messages, name), let list = response.child(messages, "ResponseMessages") else {
            throw RemoteError.decode
        }
        return list.children
    }

    // checkMessage maps an error message to a server error. Access denied reads as 403 like the other services.
    static func checkMessage(_ message: CalDAVCalendar.DAVNode) throws {
        guard message.attributes["ResponseClass"] == "Error" else {
            return
        }
        let code = message.child(messages, "ResponseCode")?.trimmedText
        throw RemoteError.server(status: code == "ErrorAccessDenied" ? 403 : 500)
    }

    // entry maps one calendar item to a CalendarEntry, or returns nil for canceled or unreadable items.
    static func entry(_ item: CalDAVCalendar.DAVNode, addresses: Set<String>, floating: TimeZone) -> CalendarEntry? {
        func text(_ name: String) -> String? {
            item.child(types, name)?.text
        }
        func flag(_ name: String) -> Bool {
            text(name)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        }
        if flag("IsCancelled") {
            return nil
        }
        guard var start = text("Start").flatMap(date), var end = text("End").flatMap(date) else {
            return nil
        }
        let isAllDay = flag("IsAllDayEvent")
        if isAllDay {
            start = midnightUTC(start, floating: floating)
            end = midnightUTC(end, floating: floating)
        }
        let response = text("MyResponseType")?.trimmingCharacters(in: .whitespacesAndNewlines)
        var others: Set<String> = []
        for list in ["RequiredAttendees", "OptionalAttendees"] {
            for attendee in item.child(types, list)?.children(types, "Attendee") ?? [] {
                let mailbox = attendee.child(types, "Mailbox")
                let address = mailbox?.child(types, "EmailAddress")?.trimmedText.lowercased() ?? ""
                let name = mailbox?.child(types, "Name")?.trimmedText.lowercased() ?? ""
                if address.isEmpty || addresses.contains(address) || addresses.contains(name) {
                    continue
                }
                others.insert(address)
            }
        }
        let organizer = item.child(types, "Organizer")?.child(types, "Mailbox")?.child(types, "EmailAddress")?
            .trimmedText.lowercased()
        if let organizer, !organizer.isEmpty, response != "Organizer", !addresses.contains(organizer) {
            others.insert(organizer)
        }
        let id = text("UID").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? item.child(types, "ItemId")?.attributes["Id"] ?? ""
        let location = text("Location").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let body = text("Body")
        let web = text("WebClientReadFormQueryString").flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
        return CalendarEntry(
            eventID: "ews:\(id)",
            title: text("Subject") ?? "",
            start: start,
            end: end,
            isAllDay: isAllDay,
            isFree: text("LegacyFreeBusyStatus")?.trimmingCharacters(in: .whitespacesAndNewlines) == "Free",
            status: status(response),
            attendeeCount: others.count,
            url: text("JoinOnlineMeetingUrl").flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) },
            location: location?.isEmpty == false ? location : nil,
            notes: body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? body : nil,
            webURL: web?.scheme == nil ? nil : web
        )
    }

    // status maps an EWS response type to the core type.
    static func status(_ response: String?) -> CalendarEntry.ParticipationStatus {
        switch response {
        case "Organizer", "Accept":
            return .accepted
        case "Tentative":
            return .tentative
        case "Decline":
            return .declined
        case "NoResponseReceived":
            return .pending
        default:
            return .unknown
        }
    }

    // midnightUTC moves an all-day boundary, which Exchange sends as midnight in the mailbox's zone, to
    // midnight UTC of the same date, like Google and CalDAV all-day events.
    static func midnightUTC(_ date: Date, floating: TimeZone) -> Date {
        var local = Foundation.Calendar(identifier: .gregorian)
        local.timeZone = floating
        var utc = Foundation.Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: local.dateComponents([.year, .month, .day], from: date)) ?? date
    }

    // date reads an xs:dateTime such as 2026-10-22T14:00:00Z, with or without fractional seconds or an offset.
    static func date(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    // stamp formats a time as an xs:dateTime in UTC.
    static func stamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    // soapRequest wraps a body in an EWS envelope and builds the POST.
    static func soapRequest(_ url: URL, body: String) -> URLRequest {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="\(soap)" xmlns:m="\(messages)" xmlns:t="\(types)">
        <soap:Header><t:RequestServerVersion Version="\(serverVersion)"/></soap:Header>
        <soap:Body>
        \(body)
        </soap:Body>
        </soap:Envelope>
        """
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/xml", forHTTPHeaderField: "Accept")
        request.httpBody = Data(envelope.utf8)
        return request
    }

    // escape makes text safe inside an XML attribute.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
