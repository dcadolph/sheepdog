import SwiftUI

import SheepdogCore

// UpdateCardView is the card that says a newer Sheepdog is out.
struct UpdateCardView: View {
    // model supplies the version, the install source and the actions.
    @Bindable var model: AlertModel

    // body lays out the card.
    var body: some View {
        if let version = model.updateVersion {
            HStack(alignment: .top, spacing: 12) {
                TugImage(name: "tug-head")
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update available")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accentText)
                    Text("Sheepdog \(version) is out.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 8) {
                        Button(action: model.onOpenUpdate) {
                            Text(primaryLabel)
                                .fixedSize()
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 14)
                                .frame(height: 24)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(Theme.onAccent)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.updateBusy)
                        Button(action: model.onRemindUpdate) {
                            Text("Remind me later")
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
                    Button(action: model.onSkipUpdate) {
                        Text("Skip this version")
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

    // primaryLabel names the first button, which installs the update when this copy can, and
    // otherwise, or after a failed install, opens the release page.
    private var primaryLabel: String {
        if model.updateBusy {
            return "Updating"
        }
        return model.updateCanInstall && !model.updateFailed ? "Update now" : "Open release page"
    }
}
