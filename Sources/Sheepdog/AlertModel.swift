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
    // takeoverLead is how long before the start the takeover opens, the full scale of its countdown ring.
    var takeoverLead: TimeInterval = 60
    // askPlace reports whether the alert asks what the user was in the middle of.
    var askPlace = false
    // heldNote is the note already saved for the meeting.
    var heldNote: String?
    // draft is the note being typed for the meeting.
    var draft = ""
    // editingInTakeover reports whether the takeover's note field is open.
    var editingInTakeover = false
    // handBack is the note being handed back after its meeting.
    var handBack: HeldPlace?
    // handBackCount is how many notes are waiting to be acknowledged.
    var handBackCount = 0
    // slackChannels are the channels Msg team can open. Msg team shows only when there is one.
    var slackChannels: [SlackChannel] = []
    // messagingTeam reports whether the takeover's Msg team row is open.
    var messagingTeam = false
    // teamChannel is the index of the channel picked in the Msg team row.
    var teamChannel = 0

    // onJoin is called when the user chooses Join.
    var onJoin: () -> Void = {}
    // onSnooze is called when the user chooses Snooze.
    var onSnooze: () -> Void = {}
    // onSkip is called when the user skips the meeting.
    var onSkip: () -> Void = {}
    // onCloseTakeover is called when the user closes the takeover without joining, snoozing or skipping.
    var onCloseTakeover: () -> Void = {}
    // onClosePill is called when the user closes the countdown pill.
    var onClosePill: () -> Void = {}
    // onSaveNote is called when the user presses Return in a note field.
    var onSaveNote: () -> Void = {}
    // onHoldPlace is called when the user opens the takeover's note field.
    var onHoldPlace: () -> Void = {}
    // onMsgTeam is called when the user opens or closes the Msg team row.
    var onMsgTeam: () -> Void = {}
    // onSendTeamMessage is called when the user picks a message to send to the team.
    var onSendTeamMessage: (TeamMessage) -> Void = { _ in }
    // onCancelNote is called when the user presses Escape in a note field.
    var onCancelNote: () -> Void = {}
    // onCopyHandBack is called when the user copies the handed back note.
    var onCopyHandBack: () -> Void = {}
    // onDoneHandBack is called when the user acknowledges the handed back note.
    var onDoneHandBack: () -> Void = {}
    // onClearHandBacks is called when the user acknowledges every handed back note at once.
    var onClearHandBacks: () -> Void = {}

    // hasStarted reports whether the meeting's start has passed.
    var hasStarted: Bool {
        guard let meeting else {
            return false
        }
        return now >= meeting.start
    }
}
