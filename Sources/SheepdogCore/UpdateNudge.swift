import Foundation

// UpdateNudge remembers which release the user was told about and when to remind them again.
public struct UpdateNudge: Sendable, Codable, Equatable {
    // firstReminder is the wait between the first notice and the first reminder.
    public static let firstReminder: TimeInterval = 7 * 86400
    // laterReminders is the wait between each reminder after the first.
    public static let laterReminders: TimeInterval = 30 * 86400
    // maxReminders is the number of reminders after which the nudge goes quiet.
    public static let maxReminders = 3

    // tag is the release tag the nudge is tracking.
    public var tag: String?
    // firstSeen is when the tracked tag was first seen.
    public var firstSeen: Date?
    // lastShown is when the user was last told about the tracked tag.
    public var lastShown: Date?
    // reminders counts the reminders shown after the first notice.
    public var reminders: Int = 0
    // skipped is the tag the user chose to skip.
    public var skipped: String?

    // init creates an empty nudge.
    public init() {}

    // see records a release tag, and restarts the schedule when the tag is new.
    public mutating func see(_ tag: String, now: Date) {
        guard tag != self.tag else {
            return
        }
        self.tag = tag
        firstSeen = now
        lastShown = nil
        reminders = 0
    }

    // due reports whether the user should be told about the tracked tag now.
    public func due(now: Date, blocked: Bool) -> Bool {
        guard !blocked, let tag, tag != skipped else {
            return false
        }
        guard let lastShown else {
            return true
        }
        guard reminders < Self.maxReminders else {
            return false
        }
        let wait = reminders == 0 ? Self.firstReminder : Self.laterReminders
        return now.timeIntervalSince(lastShown) >= wait || now < lastShown
    }

    // shown records that the user was told about the tracked tag.
    public mutating func shown(now: Date) {
        if lastShown != nil {
            reminders += 1
        }
        lastShown = now
    }

    // skip stops nudging about the tracked tag.
    public mutating func skip() {
        skipped = tag
    }
}
