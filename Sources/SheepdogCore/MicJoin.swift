import Foundation

// MicJoin decides which meeting, if any, the microphone shows the user joined. macOS reports only that
// the default input is in use, never by which app or call, so the rule is about time: a call that
// started once a meeting's alerts could begin, and is still running at its takeover mark, is that
// meeting's call. A mic already running before the window opened belongs to an earlier call, so
// back-to-back meetings keep their alarm.
public enum MicJoin {
    // joined returns the meeting the live mic counts as joining, nil when none. It needs the mic live
    // now, started at or after the meeting's earliest alert, now at or past the takeover mark, the
    // meeting unresolved and not expired. Among several it returns the earliest start, the first in
    // the list on a tie.
    public static func joined(
        _ meetings: [Meeting], states: [String: MeetingState], settings: AlertSettings, micRunning: Bool,
        micStartedAt: Date?, now: Date
    ) -> Meeting? {
        guard micRunning, let micStartedAt else {
            return nil
        }
        var best: Meeting?
        for meeting in meetings where states[meeting.id]?.resolution == nil {
            guard micStartedAt >= meeting.start.addingTimeInterval(-settings.earliestLead),
                now >= meeting.start.addingTimeInterval(-settings.takeoverLead),
                !Escalation.isExpired(meeting, settings: settings, now: now)
            else {
                continue
            }
            if best.map({ meeting.start < $0.start }) ?? true {
                best = meeting
            }
        }
        return best
    }
}
