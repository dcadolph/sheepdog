import SwiftUI

import SheepdogCore

// PillView is the small floating countdown shown during warnings.
struct PillView: View {
    // model supplies the meeting, countdown, and actions.
    @Bindable var model: AlertModel

    // body lays out the countdown row and, when asking, the note row under it.
    var body: some View {
        if let meeting = model.meeting {
            VStack(alignment: .leading, spacing: 6) {
                row(meeting)
                if let note = model.heldNote {
                    Text("Tug is holding: \(note)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.bone.opacity(0.8))
                        .lineLimit(1)
                        .frame(maxWidth: 320, alignment: .leading)
                        .padding(.leading, 38)
                } else if model.askPlace {
                    NoteField(model: model)
                        .frame(width: 300)
                        .padding(.leading, 38)
                }
            }
            .padding(.vertical, model.askPlace || model.heldNote != nil ? 6 : 0)
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: 40)
            .background(Theme.ink.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.cream.opacity(0.25), lineWidth: 1))
            .fixedSize()
        }
    }

    // row is the countdown line with Tug, the title, the clock and the buttons.
    private func row(_ meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            TugImage(name: "tug-head")
                .frame(width: 28, height: 28)
                .clipShape(Circle())
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
            Button(action: model.onClosePill) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Theme.cream.opacity(0.15), in: Circle())
                    .foregroundStyle(Theme.bone)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Hide the countdown. The chimes and the alarm still come.")
        }
        .frame(height: 28)
    }
}

// NoteField is the one-line box that asks what the user was in the middle of.
struct NoteField: View {
    // model holds the draft and the save and cancel actions.
    @Bindable var model: AlertModel
    // focusOnAppear reports whether the field takes the cursor as soon as it shows.
    var focusOnAppear = false
    // focused tracks whether the field has the cursor.
    @FocusState private var focused: Bool

    // body draws the field with a placeholder readable on the dark pill.
    var body: some View {
        if model.drawsStill {
            still
        } else {
            field
        }
    }

    // field is the live text field.
    private var field: some View {
        TextField(
            "",
            text: $model.draft,
            prompt: Text("What were you in the middle of?").foregroundStyle(Theme.bone.opacity(0.45))
        )
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Theme.cream.opacity(0.1), in: Capsule())
        .focused($focused)
        .onSubmit(model.onSaveNote)
        .onExitCommand(perform: model.onCancelNote)
        .onAppear {
            if focusOnAppear {
                focused = true
            }
        }
    }

    // still draws the field's text and caret the way the live field shows them, for rendered images.
    private var still: some View {
        HStack(spacing: 1) {
            Text(model.draft)
                .foregroundStyle(.white)
            Rectangle()
                .fill(.white)
                .frame(width: 1, height: 14)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Theme.cream.opacity(0.1), in: Capsule())
    }
}
