import Foundation

// Stage is how loudly Sheepdog is alerting for a meeting.
public enum Stage: Int, Sendable, Comparable {
    case idle
    case warning
    case takeover

    // < orders stages from quietest to loudest.
    public static func < (lhs: Stage, rhs: Stage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// Resolution is how a meeting stopped needing alerts.
public enum Resolution: String, Sendable, Equatable, Codable {
    case joined
    case skipped
}

// MeetingState is what the user has done about a meeting so far.
public struct MeetingState: Sendable, Equatable {
    // Resolution is set once the meeting is joined or skipped.
    public var resolution: Resolution?
    // SnoozedUntil is when the current snooze ends.
    public var snoozedUntil: Date?
    // SnoozeCount is how many snoozes have been used.
    public var snoozeCount: Int = 0
    // PillHidden is set when the user closes the countdown pill without resolving the meeting.
    public var pillHidden: Bool = false
    // Quieted is set when the user opens the takeover's note field, which stops the alarm sound.
    public var quieted: Bool = false
    // TakeoverClosed is set when the user closes the takeover, which leaves only the pill for the meeting.
    public var takeoverClosed: Bool = false

    // init creates an untouched state.
    public init(
        resolution: Resolution? = nil,
        snoozedUntil: Date? = nil,
        snoozeCount: Int = 0,
        pillHidden: Bool = false,
        quieted: Bool = false,
        takeoverClosed: Bool = false
    ) {
        self.resolution = resolution
        self.snoozedUntil = snoozedUntil
        self.snoozeCount = snoozeCount
        self.pillHidden = pillHidden
        self.quieted = quieted
        self.takeoverClosed = takeoverClosed
    }
}

// Escalation decides what to show for a meeting at a given moment.
public enum Escalation {
    // stage returns the alert stage for a meeting at now.
    public static func stage(for meeting: Meeting, state: MeetingState, settings: AlertSettings, now: Date) -> Stage {
        if state.resolution != nil || isExpired(meeting, settings: settings, now: now) {
            return .idle
        }
        let untilStart = meeting.start.timeIntervalSince(now)
        if untilStart > settings.earliestLead {
            return .idle
        }
        if let until = state.snoozedUntil, now < until {
            return .warning
        }
        if untilStart <= settings.takeoverLead && !state.takeoverClosed {
            return .takeover
        }
        return .warning
    }

    // isExpired reports whether the meeting is past its nag window.
    public static func isExpired(_ meeting: Meeting, settings: AlertSettings, now: Date) -> Bool {
        now >= meeting.start.addingTimeInterval(settings.nagWindow)
    }

    // isInAlertWindow reports whether the meeting is between its earliest alert and the end of its nag window.
    public static func isInAlertWindow(_ meeting: Meeting, settings: AlertSettings, now: Date) -> Bool {
        let opens = meeting.start.addingTimeInterval(-settings.earliestLead)
        return now >= opens && !isExpired(meeting, settings: settings, now: now)
    }

    // crossedWarning reports whether a warning lead fell in the interval (previous, now].
    public static func crossedWarning(for meeting: Meeting, settings: AlertSettings, previous: Date, now: Date) -> Bool {
        settings.warningLeads.contains { lead in
            let mark = meeting.start.addingTimeInterval(-lead)
            return mark > previous && mark <= now
        }
    }

    // showsPill reports whether the countdown pill should be up for a meeting in the warning stage.
    public static func showsPill(_ state: MeetingState, settings: AlertSettings) -> Bool {
        settings.showPill && !state.pillHidden
    }

    // canSnooze reports whether another snooze is allowed.
    public static func canSnooze(_ state: MeetingState, settings: AlertSettings) -> Bool {
        state.resolution == nil && state.snoozeCount < settings.maxSnoozes
    }

    // quieted returns the state with the alarm sound stopped and the takeover left up.
    public static func quieted(_ state: MeetingState) -> MeetingState {
        var next = state
        next.quieted = true
        return next
    }

    // closedTakeover returns the state with the takeover closed for good and the pill showing instead.
    public static func closedTakeover(_ state: MeetingState) -> MeetingState {
        var next = state
        next.takeoverClosed = true
        next.pillHidden = false
        return next
    }

    // snoozed returns the state after a snooze at now, or the state unchanged when no snooze is left.
    public static func snoozed(_ state: MeetingState, meeting: Meeting, settings: AlertSettings, now: Date) -> MeetingState {
        guard canSnooze(state, settings: settings) else {
            return state
        }
        var next = state
        next.snoozeCount += 1
        next.pillHidden = false
        next.quieted = false
        if now < meeting.start {
            next.snoozedUntil = min(now.addingTimeInterval(settings.snoozeBeforeStart), meeting.start)
        } else {
            next.snoozedUntil = now.addingTimeInterval(settings.snoozeAfterStart)
        }
        return next
    }

    // mostUrgent returns the unresolved meeting at the loudest stage, earliest start breaking ties. Meetings whose
    // ids are in quiet never pass the warning stage.
    public static func mostUrgent(
        _ meetings: [Meeting],
        states: [String: MeetingState],
        settings: AlertSettings,
        now: Date,
        quiet: Set<String> = []
    ) -> (meeting: Meeting, stage: Stage)? {
        var best: (meeting: Meeting, stage: Stage)?
        for meeting in meetings {
            var stage = stage(for: meeting, state: states[meeting.id] ?? MeetingState(), settings: settings, now: now)
            if quiet.contains(meeting.id) {
                stage = min(stage, .warning)
            }
            guard stage != .idle else {
                continue
            }
            if let current = best,
               current.stage > stage || (current.stage == stage && current.meeting.start <= meeting.start) {
                continue
            }
            best = (meeting, stage)
        }
        return best
    }
}
