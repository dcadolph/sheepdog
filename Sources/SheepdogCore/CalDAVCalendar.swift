import Foundation

// CalDAVCalendar reads events from a CalDAV server, such as iCloud, with PROPFIND and REPORT only.
// The server expands recurring events, so the client never does recurrence math.
public enum CalDAVCalendar {
    // iCloudURL is where iCloud discovery starts.
    public static let iCloudURL = URL(string: "https://caldav.icloud.com/")!
    // dav is the WebDAV XML namespace.
    static let dav = "DAV:"
    // caldav is the CalDAV XML namespace.
    static let caldav = "urn:ietf:params:xml:ns:caldav"
    // maxCalendars bounds how many calendars one read asks for, so a strange home cannot run away.
    static let maxCalendars = 50

    // Discovery is what sign-in learns about an account before reading any event.
    public struct Discovery: Sendable, Equatable {
        // Base is the URL discovery started from. Credentials only go to URLs it allows.
        public var base: URL
        // Home is the collection that holds the user's calendars.
        public var home: URL
        // Addresses are the user's calendar addresses, lowercased, used to find the user among attendees.
        public var addresses: [String]

        // init creates a discovery result.
        public init(base: URL, home: URL, addresses: [String]) {
            self.base = base
            self.home = home
            self.addresses = addresses
        }
    }

    // principalRequest asks a server for the signed-in user's principal.
    public static func principalRequest(_ url: URL, username: String, password: String) -> URLRequest {
        davRequest(
            url, method: "PROPFIND", depth: "0", body: propfindBody(["D:current-user-principal"]),
            username: username, password: password
        )
    }

    // homeRequest asks a principal for its calendar home and calendar addresses.
    public static func homeRequest(_ principal: URL, username: String, password: String) -> URLRequest {
        davRequest(
            principal, method: "PROPFIND", depth: "0",
            body: propfindBody(["C:calendar-home-set", "C:calendar-user-address-set"]),
            username: username, password: password
        )
    }

    // calendarsRequest lists a home's collections with their types and the components they hold.
    public static func calendarsRequest(_ home: URL, username: String, password: String) -> URLRequest {
        davRequest(
            home, method: "PROPFIND", depth: "1",
            body: propfindBody(["D:resourcetype", "D:displayname", "C:supported-calendar-component-set"]),
            username: username, password: password
        )
    }

    // eventsRequest asks one calendar for the events that overlap the window, expanded by the server.
    public static func eventsRequest(
        calendar: URL, from: Date, to: Date, username: String, password: String
    ) -> URLRequest {
        let range = #"start="\#(stamp(from))" end="\#(stamp(to))""#
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
        <D:prop><C:calendar-data><C:expand \(range)/></C:calendar-data></D:prop>
        <C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VEVENT">
        <C:time-range \(range)/>
        </C:comp-filter></C:comp-filter></C:filter>
        </C:calendar-query>
        """
        return davRequest(calendar, method: "REPORT", depth: "1", body: body, username: username, password: password)
    }

    // discover finds the user's calendar home, starting at base and then at its well-known CalDAV path.
    public static func discover(
        client: HTTPClient, base: URL, username: String, password: String
    ) async throws -> Discovery {
        var principal = try await findPrincipal(
            client: client, at: base, base: base, username: username, password: password
        )
        if principal == nil, let wellKnown = URL(string: "/.well-known/caldav", relativeTo: base)?.absoluteURL,
           wellKnown != base
        {
            principal = try await findPrincipal(
                client: client, at: wellKnown, base: base, username: username, password: password
            )
        }
        guard let principal else {
            throw RemoteError.notCalDAV
        }
        let (data, status) = try await client.send(homeRequest(principal, username: username, password: password))
        try checkStatus(status)
        guard let response = try multistatus(data).first,
              let homeHref = response.prop(caldav, "calendar-home-set")?.child(dav, "href")?.trimmedText,
              let home = resolve(homeHref, against: principal)
        else {
            throw RemoteError.notCalDAV
        }
        try checkAllowed(home, base: base)
        var addresses: [String] = []
        let hrefs = response.prop(caldav, "calendar-user-address-set")?.children(dav, "href") ?? []
        for href in hrefs {
            let text = href.trimmedText
            if text.lowercased().hasPrefix("mailto:") {
                addresses.append(String(text.dropFirst(7)).lowercased())
            }
        }
        if username.contains("@") {
            addresses.append(username.lowercased())
        }
        var seen: Set<String> = []
        return Discovery(base: base, home: home, addresses: addresses.filter { seen.insert($0).inserted })
    }

    // fetch reads every event calendar in the home and maps its events in the window to entries.
    public static func fetch(
        client: HTTPClient, discovery: Discovery, username: String, password: String, from: Date, to: Date,
        floating: TimeZone = .current
    ) async throws -> [CalendarEntry] {
        var entries: [CalendarEntry] = []
        let list = try await calendars(client: client, discovery: discovery, username: username, password: password)
        for calendar in list {
            let request = eventsRequest(calendar: calendar, from: from, to: to, username: username, password: password)
            let (data, status) = try await client.send(request)
            try checkStatus(status)
            for response in try multistatus(data) {
                guard let text = response.prop(caldav, "calendar-data")?.text else {
                    continue
                }
                entries += events(fromICS: text, addresses: discovery.addresses, floating: floating)
                    .filter { $0.end > from && $0.start < to }
            }
        }
        return entries
    }

    // calendars returns the home's collections that hold events.
    static func calendars(
        client: HTTPClient, discovery: Discovery, username: String, password: String
    ) async throws -> [URL] {
        let request = calendarsRequest(discovery.home, username: username, password: password)
        let (data, status) = try await client.send(request)
        try checkStatus(status)
        var urls: [URL] = []
        for response in try multistatus(data) {
            guard response.prop(dav, "resourcetype")?.child(caldav, "calendar") != nil else {
                continue
            }
            if let set = response.prop(caldav, "supported-calendar-component-set") {
                let names = set.children(caldav, "comp").compactMap { $0.attributes["name"]?.uppercased() }
                if !names.isEmpty, !names.contains("VEVENT") {
                    continue
                }
            }
            guard let url = resolve(response.href, against: discovery.home) else {
                continue
            }
            try checkAllowed(url, base: discovery.base)
            urls.append(url)
        }
        if urls.count > maxCalendars {
            throw RemoteError.tooManyPages
        }
        return urls
    }

    // findPrincipal asks one URL for the principal, or returns nil when that URL is not a CalDAV endpoint.
    static func findPrincipal(
        client: HTTPClient, at url: URL, base: URL, username: String, password: String
    ) async throws -> URL? {
        let (data, status) = try await client.send(principalRequest(url, username: username, password: password))
        switch status {
        case 200..<300:
            break
        case 401:
            throw RemoteError.unauthorized
        case 404, 405, 501:
            return nil
        default:
            throw RemoteError.server(status: status)
        }
        guard let responses = try? multistatus(data),
              let href = responses.lazy
                  .compactMap({ $0.prop(dav, "current-user-principal")?.child(dav, "href") }).first,
              let principal = resolve(href.trimmedText, against: url)
        else {
            return nil
        }
        try checkAllowed(principal, base: base)
        return principal
    }

    // checkAllowed refuses to send credentials anywhere but https, or the exact origin discovery started from.
    static func checkAllowed(_ url: URL, base: URL) throws {
        if url.scheme?.lowercased() == "https" {
            return
        }
        if url.scheme?.lowercased() == base.scheme?.lowercased(), url.host?.lowercased() == base.host?.lowercased(),
           url.port == base.port
        {
            return
        }
        throw RemoteError.insecureURL
    }

    // resolve turns an href from a response into an absolute URL.
    static func resolve(_ href: String, against url: URL) -> URL? {
        let text = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return nil
        }
        if let resolved = URL(string: text, relativeTo: url) {
            return resolved.absoluteURL
        }
        return text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            .flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
    }

    // davRequest builds a WebDAV request authorized with a user name and password.
    static func davRequest(
        _ url: URL, method: String, depth: String, body: String, username: String, password: String
    ) -> URLRequest {
        var request = basicRequest(url, username: username, password: password)
        request.httpMethod = method
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }

    // propfindBody builds a PROPFIND body asking for the named properties.
    static func propfindBody(_ props: [String]) -> String {
        let list = props.map { "<\($0)/>" }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop>\(list)</D:prop></D:propfind>
        """
    }

    // stamp formats a time as a CalDAV UTC date-time, such as 20261022T140000Z.
    static func stamp(_ date: Date) -> String {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0,
            c.second ?? 0
        )
    }
}

extension CalDAVCalendar {
    // Response is one resource in a multistatus reply with the properties the server found.
    struct Response {
        // Href names the resource.
        let href: String
        // Props are the property elements from propstats that succeeded.
        let props: [DAVNode]

        // prop returns the named property.
        func prop(_ namespace: String, _ name: String) -> DAVNode? {
            props.first { $0.namespace == namespace && $0.name == name }
        }
    }

    // multistatus reads a WebDAV multistatus body or throws RemoteError.decode.
    static func multistatus(_ data: Data) throws -> [Response] {
        guard let root = XMLTree.parse(data), root.namespace == dav, root.name == "multistatus" else {
            throw RemoteError.decode
        }
        return root.children(dav, "response").compactMap { response in
            guard let href = response.child(dav, "href")?.trimmedText else {
                return nil
            }
            var props: [DAVNode] = []
            for propstat in response.children(dav, "propstat") {
                let status = propstat.child(dav, "status")?.trimmedText ?? ""
                if !status.isEmpty, !status.contains(" 2") {
                    continue
                }
                props += propstat.child(dav, "prop")?.children ?? []
            }
            return Response(href: href, props: props)
        }
    }

    // DAVNode is one parsed element with its namespace, attributes, text and children.
    final class DAVNode {
        // Name is the local name.
        let name: String
        // Namespace is the namespace URI.
        let namespace: String
        // Attributes are the element's attributes by local name.
        let attributes: [String: String]
        // Text is the element's own character data.
        var text = ""
        // Children are the child elements in order.
        var children: [DAVNode] = []

        // init creates an element with no text or children.
        init(name: String, namespace: String, attributes: [String: String]) {
            self.name = name
            self.namespace = namespace
            self.attributes = attributes
        }

        // trimmedText is the text without surrounding whitespace.
        var trimmedText: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // child returns the first child with the name.
        func child(_ namespace: String, _ name: String) -> DAVNode? {
            children.first { $0.namespace == namespace && $0.name == name }
        }

        // children returns every child with the name.
        func children(_ namespace: String, _ name: String) -> [DAVNode] {
            children.filter { $0.namespace == namespace && $0.name == name }
        }
    }

    // XMLTree builds an element tree with XMLParser.
    final class XMLTree: NSObject, XMLParserDelegate {
        // stack holds the open elements.
        private var stack: [DAVNode] = []
        // root is the document element once it closes.
        private var root: DAVNode?

        // parse returns the document element, or nil when the data is not well-formed XML.
        static func parse(_ data: Data) -> DAVNode? {
            let tree = XMLTree()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = tree
            guard parser.parse() else {
                return nil
            }
            return tree.root
        }

        // parser opens an element.
        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            stack.append(DAVNode(name: elementName, namespace: namespaceURI ?? "", attributes: attributes))
        }

        // parser closes an element and attaches it to its parent.
        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
        ) {
            guard let element = stack.popLast() else {
                return
            }
            if let parent = stack.last {
                parent.children.append(element)
            } else {
                root = element
            }
        }

        // parser adds character data to the open element.
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        // parser adds a CDATA block to the open element.
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
        }
    }
}

extension CalDAVCalendar {
    // Property is one iCalendar content line: its name, parameters and raw value.
    struct Property: Equatable {
        // Name is the upper-cased property name.
        let name: String
        // Params are the parameters by upper-cased name, with quotes removed.
        let params: [String: String]
        // Value is the raw value, still escaped.
        let value: String
    }

    // events maps every VEVENT in an iCalendar body to an entry, skipping canceled and unreadable ones.
    static func events(fromICS text: String, addresses: [String], floating: TimeZone) -> [CalendarEntry] {
        components(unfold(text)).compactMap { entry($0, addresses: addresses, floating: floating) }
    }

    // unfold joins folded lines, where a line that starts with a space or tab continues the one before.
    static func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines
    }

    // property splits a content line into its name, parameters and value, honoring quoted parameter values.
    static func property(_ line: String) -> Property? {
        var parts: [String] = []
        var current = ""
        var quoted = false
        var value: String?
        for (index, char) in zip(line.indices, line) {
            if char == "\"" {
                quoted.toggle()
                current.append(char)
            } else if char == ";", !quoted {
                parts.append(current)
                current = ""
            } else if char == ":", !quoted {
                parts.append(current)
                value = String(line[line.index(after: index)...])
                break
            } else {
                current.append(char)
            }
        }
        guard let value, let name = parts.first, !name.isEmpty else {
            return nil
        }
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "=") else {
                continue
            }
            let key = part[..<equals].uppercased()
            params[key] = part[part.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Property(name: name.uppercased(), params: params, value: value)
    }

    // components returns the properties of each VEVENT, leaving out nested components such as VALARM.
    static func components(_ lines: [String]) -> [[Property]] {
        var events: [[Property]] = []
        var current: [Property]?
        var nested = 0
        for line in lines {
            guard let prop = property(line) else {
                continue
            }
            let kind = prop.value.trimmingCharacters(in: .whitespaces).uppercased()
            switch prop.name {
            case "BEGIN":
                if current != nil {
                    nested += 1
                } else if kind == "VEVENT" {
                    current = []
                }
            case "END":
                if current != nil {
                    if nested > 0 {
                        nested -= 1
                    } else if kind == "VEVENT", let event = current {
                        events.append(event)
                        current = nil
                    }
                }
            default:
                if nested == 0 {
                    current?.append(prop)
                }
            }
        }
        return events
    }

    // entry maps one VEVENT's properties to a CalendarEntry, or returns nil for canceled or unreadable events.
    static func entry(_ props: [Property], addresses: [String], floating: TimeZone) -> CalendarEntry? {
        func first(_ name: String) -> Property? {
            props.first { $0.name == name }
        }
        func text(_ name: String) -> String? {
            first(name).map { unescape($0.value) }
        }
        if first("STATUS")?.value.uppercased() == "CANCELLED" {
            return nil
        }
        guard let startProp = first("DTSTART"), let start = date(startProp, floating: floating) else {
            return nil
        }
        let end: Date
        if let endProp = first("DTEND"), let value = date(endProp, floating: floating) {
            end = value.date
        } else if let duration = first("DURATION").flatMap({ seconds($0.value) }) {
            end = start.date.addingTimeInterval(duration)
        } else {
            end = start.isDate ? start.date.addingTimeInterval(86400) : start.date
        }
        let mine = Set(addresses)
        var me: Property?
        var others: Set<String> = []
        for attendee in props where attendee.name == "ATTENDEE" {
            let address = mailAddress(attendee.value)
            let name = attendee.params["CN"]?.lowercased() ?? ""
            if mine.contains(address) || mine.contains(name) {
                me = me ?? attendee
                continue
            }
            let kind = attendee.params["CUTYPE"]?.uppercased() ?? "INDIVIDUAL"
            if kind == "ROOM" || kind == "RESOURCE" || address.isEmpty {
                continue
            }
            others.insert(address)
        }
        let organizer = first("ORGANIZER").map { mailAddress($0.value) }
        if let organizer, !organizer.isEmpty, !mine.contains(organizer) {
            others.insert(organizer)
        }
        let status: CalendarEntry.ParticipationStatus
        if let me {
            status = participation(me.params["PARTSTAT"])
        } else if let organizer, mine.contains(organizer) {
            status = .accepted
        } else {
            status = .unknown
        }
        return CalendarEntry(
            eventID: "caldav:\(first("UID")?.value ?? "")",
            title: text("SUMMARY") ?? "",
            start: start.date,
            end: end,
            isAllDay: start.isDate,
            isFree: first("TRANSP")?.value.uppercased() == "TRANSPARENT",
            status: status,
            attendeeCount: others.count,
            url: first("URL").flatMap { URL(string: $0.value.trimmingCharacters(in: .whitespaces)) },
            location: text("LOCATION"),
            notes: text("DESCRIPTION")
        )
    }

    // participation maps an iCalendar PARTSTAT to the core type.
    static func participation(_ value: String?) -> CalendarEntry.ParticipationStatus {
        switch value?.uppercased() {
        case "ACCEPTED", "DELEGATED":
            return .accepted
        case "TENTATIVE":
            return .tentative
        case "DECLINED":
            return .declined
        case "NEEDS-ACTION":
            return .pending
        default:
            return .unknown
        }
    }

    // mailAddress returns the lowercased address of a mailto value, or an empty string for other values.
    static func mailAddress(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard text.lowercased().hasPrefix("mailto:") else {
            return ""
        }
        return String(text.dropFirst(7)).lowercased()
    }

    // unescape decodes iCalendar text escapes for backslash, semicolon, comma and newline.
    static func unescape(_ value: String) -> String {
        var out = ""
        var escaping = false
        for char in value {
            if escaping {
                switch char {
                case "n", "N":
                    out.append("\n")
                case "\\", ";", ",":
                    out.append(char)
                default:
                    out.append("\\")
                    out.append(char)
                }
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                out.append(char)
            }
        }
        if escaping {
            out.append("\\")
        }
        return out
    }

    // date reads a DATE or DATE-TIME value. A DATE is midnight UTC, like Google's all-day events. A
    // DATE-TIME is UTC with a Z, in its TZID zone when one is named and known, else in the floating zone.
    static func date(_ prop: Property, floating: TimeZone) -> (date: Date, isDate: Bool)? {
        let value = Array(prop.value.trimmingCharacters(in: .whitespaces))
        let isDate = prop.params["VALUE"]?.uppercased() == "DATE" || value.count == 8
        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= value.count else {
                return nil
            }
            return Int(String(value[range]))
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8) else {
            return nil
        }
        var parts = DateComponents(year: year, month: month, day: day)
        let zone: TimeZone
        if isDate {
            zone = TimeZone(identifier: "UTC")!
        } else {
            guard value.count >= 15, value[8] == "T", let hour = number(9..<11), let minute = number(11..<13),
                  let second = number(13..<15)
            else {
                return nil
            }
            parts.hour = hour
            parts.minute = minute
            parts.second = second
            if value.count > 15, value[15] == "Z" {
                zone = TimeZone(identifier: "UTC")!
            } else {
                zone = prop.params["TZID"].flatMap(timeZone) ?? floating
            }
        }
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: parts).map { ($0, isDate) }
    }

    // timeZone finds a zone by TZID, including ids with a vendor prefix such as /mozilla.org/.../America/Chicago.
    static func timeZone(_ id: String) -> TimeZone? {
        if let zone = TimeZone(identifier: id) {
            return zone
        }
        let parts = id.split(separator: "/")
        guard parts.count >= 2 else {
            return nil
        }
        return TimeZone(identifier: parts.suffix(2).joined(separator: "/"))
    }

    // seconds reads an iCalendar DURATION such as PT45M, P1DT2H or P1W.
    static func seconds(_ value: String) -> TimeInterval? {
        var text = Substring(value.trimmingCharacters(in: .whitespaces).uppercased())
        var sign: TimeInterval = 1
        if text.first == "-" || text.first == "+" {
            sign = text.first == "-" ? -1 : 1
            text = text.dropFirst()
        }
        guard text.first == "P" else {
            return nil
        }
        var total: TimeInterval = 0
        var digits = ""
        var inTime = false
        for char in text.dropFirst() {
            if char.isNumber {
                digits.append(char)
                continue
            }
            if char == "T" {
                inTime = true
                continue
            }
            guard let amount = TimeInterval(digits) else {
                return nil
            }
            digits = ""
            switch (char, inTime) {
            case ("W", false):
                total += amount * 604_800
            case ("D", false):
                total += amount * 86400
            case ("H", true):
                total += amount * 3600
            case ("M", true):
                total += amount * 60
            case ("S", true):
                total += amount
            default:
                return nil
            }
        }
        return digits.isEmpty ? sign * total : nil
    }
}
