import Foundation

// UpdateGate decides whether the moment is quiet enough to install an update.
public enum UpdateGate {
    // IdleSeconds is how long the Mac must sit untouched before it counts as quiet.
    public static let idleSeconds: TimeInterval = 30
    // MeetingLead is how far ahead of a meeting start the gate closes.
    public static let meetingLead: TimeInterval = 15 * 60

    // quiet reports whether nothing is happening that an install would interrupt.
    public static func quiet(
        idleSeconds idle: TimeInterval, busy: Bool, offDuty: Bool,
        meetings: [(start: Date, end: Date)], now: Date
    ) -> Bool {
        if busy || offDuty || idle < idleSeconds { return false }
        let soon = now.addingTimeInterval(meetingLead)
        return !meetings.contains { meeting in
            (meeting.start >= now && meeting.start <= soon) || (meeting.start <= now && now < meeting.end)
        }
    }
}
