import Foundation

// EntryMerge combines entries from several calendar sources into one list without duplicates.
public enum EntryMerge {
    // merge keeps one entry per meeting, in first-seen order. Copies share a meeting when they have the
    // same normalized title and start second and their join links do not disagree: at least one has no
    // link, or both links have the same host and path. Copies with different links are separate meetings.
    // A later copy replaces an earlier one only when it has a join link and the earlier one does not.
    // The kept copy's status is the first known status among its copies, in source order, so a direct
    // provider listed first outranks Apple Calendar's cached answer.
    public static func merge(_ sources: [[CalendarEntry]]) -> [CalendarEntry] {
        var order: [String] = []
        var kept: [String: [CalendarEntry]] = [:]
        for entry in sources.joined() {
            let key = self.key(entry)
            guard var group = kept[key] else {
                order.append(key)
                kept[key] = [entry]
                continue
            }
            let link = JoinLinkFinder.find(in: entry)
            guard let index = group.firstIndex(where: { sameLink(JoinLinkFinder.find(in: $0), link) }) else {
                group.append(entry)
                kept[key] = group
                continue
            }
            let existing = group[index]
            var member = existing
            if JoinLinkFinder.find(in: existing) == nil && link != nil {
                member = entry
            }
            member.status = reconciledStatus(existing: existing.status, incoming: entry.status)
            group[index] = member
            kept[key] = group
        }
        return order.flatMap { kept[$0] ?? [] }
    }

    // key identifies an event across sources by its normalized title and start second.
    static func key(_ entry: CalendarEntry) -> String {
        let title = entry.title
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return "\(title)|\(Int(entry.start.timeIntervalSince1970))"
    }

    // sameLink reports whether two copies' join links allow them to be one meeting: either is missing,
    // or both have the same lowercased host and path. The query is ignored because Teams puts tracking
    // context there and Zoom puts the passcode there.
    static func sameLink(_ a: JoinLink?, _ b: JoinLink?) -> Bool {
        guard let a, let b else {
            return true
        }
        return a.web.host?.lowercased() == b.web.host?.lowercased()
            && a.web.path.lowercased() == b.web.path.lowercased()
    }

    // reconciledStatus returns the existing status when it is known, else the incoming one.
    static func reconciledStatus(
        existing: CalendarEntry.ParticipationStatus, incoming: CalendarEntry.ParticipationStatus
    ) -> CalendarEntry.ParticipationStatus {
        existing != .unknown ? existing : incoming
    }
}
