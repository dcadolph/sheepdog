import SwiftUI

import SheepdogCore

// TakeoverView is the full-screen alarm card.
struct TakeoverView: View {
    // model supplies the meeting, countdown, and actions.
    @Bindable var model: AlertModel

    // body lays out the card over a dimmed backdrop.
    var body: some View {
        ZStack {
            Theme.ink.opacity(0.88).ignoresSafeArea()
            if let meeting = model.meeting {
                card(meeting)
            }
        }
    }

    // card is the centered alert content.
    private func card(_ meeting: Meeting) -> some View {
        VStack(spacing: 28) {
            ZStack {
                TimelineView(.animation) { context in
                    PulseRing(phase: PulseRing.phase(at: context.date))
                }
                TugImage(name: "tug")
                    .frame(width: 148, height: 148)
            }

            VStack(spacing: 10) {
                Text("TUG SAYS IT'S TIME")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Theme.cream)
                Text(meeting.title)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 900)
                Text(Countdown.phrase(start: meeting.start, now: model.now))
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.hasStarted ? Theme.late : Theme.bone)
                Text(linkCaption(meeting))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.bone.opacity(0.7))
            }

            VStack(spacing: 14) {
                Button(action: model.onJoin) {
                    Text(meeting.link == nil ? "I'm there" : "Join now")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(width: 320, height: 60)
                        .background(Theme.cream, in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                HStack(spacing: 14) {
                    Button(action: model.onSnooze) {
                        Text(snoozeLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 220, height: 44)
                            .background(Theme.bone.opacity(model.snoozesLeft > 0 ? 0.16 : 0.06), in: Capsule())
                            .foregroundStyle(Theme.bone.opacity(model.snoozesLeft > 0 ? 1 : 0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.snoozesLeft == 0)

                    Button(action: model.onSkip) {
                        Text("I'm skipping this one")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 220, height: 44)
                            .overlay(Capsule().stroke(Theme.bone.opacity(0.3), lineWidth: 1.5))
                            .foregroundStyle(Theme.bone.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(56)
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

// PulseRing is the ring that swells out from Tug and fades, once per period.
struct PulseRing: View {
    // period is the length of one pulse in seconds.
    static let period: TimeInterval = 1.1

    // phase is how far through the pulse the ring is, from 0 to 1.
    let phase: Double

    // phase returns the pulse position at a moment, so the ring is a pure function of time.
    static func phase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    // body draws the ring eased out toward its largest, faintest size.
    var body: some View {
        let eased = 1 - (1 - phase) * (1 - phase)
        Circle()
            .stroke(Theme.cream.opacity(0.35), lineWidth: 6)
            .frame(width: 168, height: 168)
            .scaleEffect(0.92 + 0.26 * eased)
            .opacity(1 - eased)
    }
}
