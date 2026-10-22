import Foundation

// HeldPlace is what the user was in the middle of when a meeting pulled them away.
public struct HeldPlace: Sendable, Codable, Equatable, Identifiable {
    // ID is the id of the meeting the note was written for.
    public var id: String
    // Title is the meeting's title, shown when the note comes back.
    public var title: String
    // Note is exactly what the user typed.
    public var note: String
    // SavedAt is when the note was last saved.
    public var savedAt: Date
    // MeetingEnd is when the meeting is scheduled to end.
    public var meetingEnd: Date
    // Resolution is how the meeting was resolved, once it was.
    public var resolution: Resolution?
    // HandedBackAt is when the note first came back, or nil while it is still being held.
    public var handedBackAt: Date?

    // init creates a held note.
    public init(
        id: String,
        title: String,
        note: String,
        savedAt: Date,
        meetingEnd: Date,
        resolution: Resolution? = nil,
        handedBackAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.savedAt = savedAt
        self.meetingEnd = meetingEnd
        self.resolution = resolution
        self.handedBackAt = handedBackAt
    }
}

// PlaceKeeper decides when held notes come back and when they are dropped.
public enum PlaceKeeper {
    // micGrace is how long past the scheduled end a note waits for the mic to go idle.
    public static let micGrace: TimeInterval = 30 * 60
    // expiryHour is the local hour on the next morning when an unacknowledged note is dropped.
    public static let expiryHour = 4

    // isDue reports whether a note should be handed back at now.
    public static func isDue(_ place: HeldPlace, now: Date, micInUse: Bool) -> Bool {
        if place.handedBackAt != nil || place.resolution == .skipped {
            return true
        }
        if now < place.meetingEnd {
            return false
        }
        return !micInUse || now >= place.meetingEnd.addingTimeInterval(micGrace)
    }

    // handedBack returns the notes with every newly due note stamped as handed back at now.
    public static func handedBack(_ places: [HeldPlace], now: Date, micInUse: Bool) -> [HeldPlace] {
        places.map { place in
            var next = place
            if next.handedBackAt == nil && isDue(place, now: now, micInUse: micInUse) {
                next.handedBackAt = now
            }
            return next
        }
    }

    // queue returns the handed back notes, newest first, the way macOS stacks alerts.
    public static func queue(_ places: [HeldPlace]) -> [HeldPlace] {
        places
            .filter { $0.handedBackAt != nil }
            .sorted { ($0.handedBackAt!, $0.savedAt) > ($1.handedBackAt!, $1.savedAt) }
    }

    // cleared returns the notes with every handed back note dropped, keeping notes still held.
    public static func cleared(_ places: [HeldPlace]) -> [HeldPlace] {
        places.filter { $0.handedBackAt == nil }
    }

    // expiry returns when a note is dropped: the first expiryHour after it came back, or after the
    // latest it could come back while it is still held.
    public static func expiry(of place: HeldPlace, calendar: Calendar) -> Date {
        let from = place.handedBackAt ?? place.meetingEnd.addingTimeInterval(micGrace)
        let mark = DateComponents(hour: expiryHour, minute: 0, second: 0)
        return calendar.nextDate(after: from, matching: mark, matchingPolicy: .nextTime) ?? from.addingTimeInterval(86400)
    }

    // pruned drops the notes that have expired at now.
    public static func pruned(_ places: [HeldPlace], now: Date, calendar: Calendar) -> [HeldPlace] {
        places.filter { now < expiry(of: $0, calendar: calendar) }
    }
}
