import SwiftUI

import SheepdogCore

// SetupCardView is the card that says Tug may be missing a calendar.
struct SetupCardView: View {
    // model supplies the hints and the actions.
    @Bindable var model: AlertModel

    // body lays out the card.
    var body: some View {
        if let top = model.setupHints.first {
            HStack(alignment: .top, spacing: 12) {
                TugImage(name: "tug-head")
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar setup")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accentText)
                    Text(top.message)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = top.detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(model.setupHints.dropFirst(), id: \.self) { hint in
                        Text(hint.message)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Button(action: model.onOpenSetup) {
                            Text("Open Calendars settings")
                                .fixedSize()
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 14)
                                .frame(height: 24)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(Theme.onAccent)
                        }
                        .buttonStyle(.plain)
                        Button(action: model.onLaterSetup) {
                            Text("Later")
                                .fixedSize()
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .frame(height: 24)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.text)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                    Button(action: model.onSilenceSetup) {
                        Text("Don't ask again")
                            .fixedSize()
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 384)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
        }
    }
}
