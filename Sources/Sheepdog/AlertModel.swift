import Foundation
import Observation

import SheepdogCore

// AlertModel is the state the takeover and pill views render.
@MainActor
@Observable
final class AlertModel {
    // meeting is the meeting being alerted for.
    var meeting: Meeting?
    // now is the current time, updated every tick so countdowns move.
    var now = Date()
    // snoozesLeft is how many snoozes remain for the meeting.
    var snoozesLeft = 0
    // snoozeLength is how long the next snooze lasts, in seconds.
    var snoozeLength: TimeInterval = 60

    // onJoin is called when the user chooses Join.
    var onJoin: () -> Void = {}
    // onSnooze is called when the user chooses Snooze.
    var onSnooze: () -> Void = {}
    // onSkip is called when the user skips the meeting.
    var onSkip: () -> Void = {}

    // hasStarted reports whether the meeting's start has passed.
    var hasStarted: Bool {
        guard let meeting else {
            return false
        }
        return now >= meeting.start
    }
}
