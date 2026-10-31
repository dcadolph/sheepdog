import Foundation

// SetupCalendar is one calendar in an Apple Calendar account.
public struct SetupCalendar: Sendable, Codable, Equatable {
    // id is the calendar's identifier on this Mac.
    public var id: String
    // title is the calendar's name.
    public var title: String

    // init creates a calendar.
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

// CalendarChoice applies the calendars the user unchecked. The hidden list is an exclusion list, so a
// new calendar alerts at once and an id from another Mac or a removed calendar changes nothing.
public enum CalendarChoice {
    // allowed returns the ids in all that are not hidden, in their order.
    public static func allowed(all: [String], hidden: Set<String>) -> [String] {
        all.filter { !hidden.contains($0) }
    }

    // summary says how many of a source's calendars Tug reads, such as "5 calendars" or "3 of 5 calendars".
    public static func summary(total: Int, hidden: Int) -> String {
        let noun = total == 1 ? "calendar" : "calendars"
        let hidden = min(max(hidden, 0), total)
        return hidden == 0 ? "\(total) \(noun)" : "\(total - hidden) of \(total) \(noun)"
    }
}
