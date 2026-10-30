import SwiftUI

import SheepdogCore

// NoticeCardView is the card that tells the user something once, such as an update that installed.
struct NoticeCardView: View {
    // model supplies the notice and the actions.
    @Bindable var model: AlertModel

    // body lays out the card.
    var body: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: 12) {
                TugImage(name: "tug-head")
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(notice.body)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(action: model.onNoticeAction) {
                            Text(notice.button)
                                .fixedSize()
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 14)
                                .frame(height: 24)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(Theme.onAccent)
                        }
                        .buttonStyle(.plain)
                        Button(action: model.onDismissNotice) {
                            Text("Dismiss")
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
