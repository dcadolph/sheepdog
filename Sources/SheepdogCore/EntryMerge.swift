import Foundation

// EntryMerge combines entries from several calendar sources into one list without duplicates.
public enum EntryMerge {
    // merge keeps one entry per normalized title and start time, in first-seen order.
    // A later duplicate replaces an earlier one only when it has a join link and the earlier one does not.
    public static func merge(_ sources: [[CalendarEntry]]) -> [CalendarEntry] {
        var order: [String] = []
        var kept: [String: CalendarEntry] = [:]
        for entry in sources.joined() {
            let key = self.key(entry)
            guard let existing = kept[key] else {
                order.append(key)
                kept[key] = entry
                continue
            }
            if JoinLinkFinder.find(in: existing) == nil && JoinLinkFinder.find(in: entry) != nil {
                kept[key] = entry
            }
        }
        return order.compactMap { kept[$0] }
    }

    // key identifies an event across sources by its normalized title and start second.
    static func key(_ entry: CalendarEntry) -> String {
        let title = entry.title
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return "\(title)|\(Int(entry.start.timeIntervalSince1970))"
    }
}
