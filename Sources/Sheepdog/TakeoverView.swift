import SwiftUI

import SheepdogCore

// TakeoverView is the full-screen alarm card.
struct TakeoverView: View {
    // model supplies the meeting, countdown, and actions.
    @Bindable var model: AlertModel

    // body lays out the card over a dimmed backdrop.
    var body: some View {
        ZStack {
            Theme.background.opacity(0.88).ignoresSafeArea()
            if let meeting = model.meeting {
                card(meeting)
            }
        }
    }

    // card is the centered alert content.
    private func card(_ meeting: Meeting) -> some View {
        VStack(spacing: 28) {
            ZStack {
                CountdownRing(
                    fraction: Countdown.remaining(start: meeting.start, now: model.now, span: model.takeoverLead),
                    late: model.hasStarted
                )
                TugImage(name: "tug")
                    .frame(width: 148, height: 148)
                closeButton
                    .offset(x: 200, y: -110)
            }

            VStack(spacing: 10) {
                Text("TUG SAYS IT'S TIME")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Theme.accentText)
                Text(meeting.title)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 900)
                Text(Countdown.phrase(start: meeting.start, now: model.now))
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.hasStarted ? Theme.late : Theme.text)
                Text(linkCaption(meeting))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            VStack(spacing: 14) {
                Button(action: model.onJoin) {
                    Text(meeting.link == nil ? "I'll attend" : "Join now")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(width: 320, height: 60)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                HStack(spacing: 14) {
                    Button(action: model.onSnooze) {
                        Text(snoozeLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 220, height: 44)
                            .background(Theme.text.opacity(model.snoozesLeft > 0 ? 0.16 : 0.06), in: Capsule())
                            .foregroundStyle(Theme.text.opacity(model.snoozesLeft > 0 ? 1 : 0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.snoozesLeft == 0)

                    Button(action: model.onSkip) {
                        Text("I'm skipping this one")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 220, height: 44)
                            .overlay(Capsule().stroke(Theme.text.opacity(0.3), lineWidth: 1.5))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }

                placeRow
            }
        }
        .padding(56)
    }

    // placeRow offers to hold the user's place and to message the team, shows the open note field or
    // Let them know row, or shows the held note.
    @ViewBuilder
    private var placeRow: some View {
        if model.messagingTeam {
            teamRow
                .padding(.top, 6)
        } else if let note = model.heldNote {
            Text("Tug is holding: \(note)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(maxWidth: 454)
                .padding(.top, 6)
            if !model.slackChannels.isEmpty {
                msgTeamButton
            }
        } else if model.editingInTakeover {
            NoteField(model: model, focusOnAppear: true)
                .frame(width: 454)
                .padding(.top, 6)
        } else if model.askPlace || !model.slackChannels.isEmpty {
            HStack(spacing: 28) {
                if model.askPlace {
                    Button(action: model.onHoldPlace) {
                        Text("Hold my place")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accentText)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .help("Jot down what you were in the middle of. Tug hands it back after the meeting.")
                }
                if !model.slackChannels.isEmpty {
                    msgTeamButton
                }
            }
            .padding(.top, 6)
        }
    }

    // msgTeamButton opens the row that messages the team in Slack.
    private var msgTeamButton: some View {
        Button(action: model.onMsgTeam) {
            Text("Let them know")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accentText)
                .underline()
        }
        .buttonStyle(.plain)
        .help("Copy a message about this meeting and open your team's Slack channel.")
    }

    // teamRow picks a channel when there are several, then a message to paste into it.
    private var teamRow: some View {
        VStack(spacing: 12) {
            if model.slackChannels.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(model.slackChannels.enumerated()), id: \.element.id) { index, channel in
                        let picked = index == model.teamChannel
                        Button {
                            model.teamChannel = index
                        } label: {
                            Text(channel.label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Theme.accent.opacity(picked ? 0.9 : 0.12), in: Capsule())
                                .foregroundStyle(picked ? Theme.onAccent : Theme.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 454)
            }
            HStack(spacing: 14) {
                Button {
                    model.onSendTeamMessage(.runningLate)
                } label: {
                    Text("Running late")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(width: 220, height: 44)
                        .background(Theme.text.opacity(0.16), in: Capsule())
                        .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)

                Button {
                    model.onSendTeamMessage(.cantMake)
                } label: {
                    Text("Can't make it")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(width: 220, height: 44)
                        .overlay(Capsule().stroke(Theme.text.opacity(0.3), lineWidth: 1.5))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Text("Copies the message and opens Slack. Paste to send.")
                    .foregroundStyle(Theme.muted)
                Button(action: model.onMsgTeam) {
                    Text("Cancel")
                        .foregroundStyle(Theme.accentText)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }

    // closeButton closes the alarm back to the countdown pill without joining, snoozing or skipping.
    private var closeButton: some View {
        Button(action: model.onCloseTakeover) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.18), in: Circle())
                .foregroundStyle(Theme.text)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close this alarm. The countdown stays at the top until the meeting.")
    }

    // snoozeLabel describes the snooze button, including what is left.
    private var snoozeLabel: String {
        guard model.snoozesLeft > 0 else {
            return "Tug is out of patience"
        }
        let length = model.snoozeLength >= 60 ? "\(Int(model.snoozeLength / 60)) min" : "\(Int(model.snoozeLength)) sec"
        return "Snooze \(length) (\(model.snoozesLeft) left)"
    }

    // linkCaption names the meeting service, or says there is no link.
    private func linkCaption(_ meeting: Meeting) -> String {
        guard let link = meeting.link else {
            return "No join link found in this event"
        }
        return "Opens in \(link.provider.rawValue)"
    }
}

// CountdownRing is the ring around Tug that drains counterclockwise back to twelve o'clock at the start.
// It eases across each one-second tick, so it moves smoothly without a clock of its own.
struct CountdownRing: View {
    // fraction is the share of the takeover lead left before the start, from 0 to 1.
    let fraction: Double
    // late reports whether the meeting has started, which fills the ring in the late color.
    let late: Bool

    // body draws a faint track under the arc of time left.
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: late ? 1 : fraction)
                .stroke(late ? Theme.late : Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(late ? nil : .linear(duration: 1), value: fraction)
        .frame(width: 172, height: 172)
    }
}
