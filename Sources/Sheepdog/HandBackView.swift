import SwiftUI

import SheepdogCore

// HandBackView is the card that gives the user back what they were in the middle of.
struct HandBackView: View {
    // model supplies the note, how many are waiting, and the actions.
    @Bindable var model: AlertModel

    // body lays out the card.
    var body: some View {
        if let place = model.handBack {
            HStack(alignment: .top, spacing: 12) {
                TugImage(name: "tug-head")
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before \(place.title) you were:")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accentText)
                        .lineLimit(1)
                    Text(place.note)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Button(action: model.onCopyHandBack) {
                            Text("Copy")
                                .fixedSize()
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .frame(height: 24)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.text)
                        }
                        .buttonStyle(.plain)
                        Button(action: model.onDoneHandBack) {
                            Text("Done")
                                .fixedSize()
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 14)
                                .frame(height: 24)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(Theme.onAccent)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if model.handBackCount > 1 {
                            Text("+\(model.handBackCount - 1) more")
                                .fixedSize()
                                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(Theme.muted)
                            Button(action: model.onClearHandBacks) {
                                Text("Clear all")
                                    .fixedSize()
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.muted)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .frame(width: 360)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
        }
    }
}
