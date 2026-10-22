import SwiftUI

import SheepdogCore

// PillView is the small floating countdown shown during warnings.
struct PillView: View {
    // model supplies the meeting, countdown, and actions.
    @Bindable var model: AlertModel

    // body lays out the capsule.
    var body: some View {
        if let meeting = model.meeting {
            HStack(spacing: 10) {
                Image(systemName: "dog.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28, height: 28)
                    .background(Theme.cream, in: Circle())
                Text(meeting.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                Text(Countdown.clock(meeting.start.timeIntervalSince(model.now)))
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.hasStarted ? Theme.late : Theme.cream)
                if meeting.link != nil {
                    Button(action: model.onJoin) {
                        Text("Join")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background(Theme.cream, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 40)
            .background(Theme.ink.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(Theme.cream.opacity(0.25), lineWidth: 1))
            .fixedSize()
        }
    }
}
