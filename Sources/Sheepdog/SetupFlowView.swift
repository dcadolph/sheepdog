import Observation
import SwiftUI

import SheepdogCore

// SetupFlowState is the setup window's place in its steps and the choices made so far.
@MainActor
@Observable
final class SetupFlowState {
    // steps are the steps this run of the window shows, in order.
    var steps: [SetupStep]
    // index is the step showing.
    var index = 0
    // upgrade reports that the window opened for an upgrade rather than a fresh install.
    var upgrade: Bool
    // startAtLogin is the Done step's login choice.
    var startAtLogin: Bool
    // askingAccess reports that the macOS Calendar prompt is up.
    var askingAccess = false
    // needsLoginApproval reports that macOS wants the login item approved after Done.
    var needsLoginApproval = false

    // init starts the window at its first step.
    init(steps: [SetupStep], upgrade: Bool, startAtLogin: Bool) {
        self.steps = steps
        self.upgrade = upgrade
        self.startAtLogin = startAtLogin
    }

    // step is the step showing.
    var step: SetupStep {
        steps[min(index, steps.count - 1)]
    }

    // title is the heading for a step, which names the outfits as new on an upgrade.
    func title(_ step: SetupStep) -> String {
        upgrade && step == .dressUp ? "What's new: Tug dresses up" : step.title
    }

    // advance moves to the next step.
    func advance() {
        index = min(index + 1, steps.count - 1)
    }

    // canGoBack reports whether Back has a step to return to. The access step is never returned to, since
    // its prompt shows only once.
    var canGoBack: Bool {
        index > 0 && steps[index - 1] != .access && !needsLoginApproval
    }
}

// SetupFlowView walks a new user through calendar access, calendars, when Tug barks, outfits and login.
struct SetupFlowView: View {
    // state is the step showing and the choices made.
    @Bindable var state: SetupFlowState
    // store holds the live settings.
    @Bindable var store: SettingsStore
    // accounts holds the calendar sign-ins.
    let accounts: Accounts
    // setupFacts gathers what Tug sees.
    let setupFacts: () -> SetupFacts
    // onSourcesChanged rereads the calendars after a source changes.
    let onSourcesChanged: () -> Void
    // onAllowAccess opens Calendar privacy settings.
    let onAllowAccess: () -> Void
    // onRequestAccess fires the macOS Calendar prompt and reports whether access was granted.
    let onRequestAccess: () async -> Bool
    // onTestAlarm runs a full takeover with a fake meeting.
    let onTestAlarm: () -> Void
    // onDone applies the login choice and reports whether macOS wants it approved.
    let onDone: (Bool) -> Bool
    // onClose closes the window.
    let onClose: () -> Void
    // onOpenLoginItems shows the Login Items pane.
    let onOpenLoginItems: () -> Void
    // facts is what Tug saw when the connect step last looked.
    @State private var facts: SetupFacts?
    // leadsText is the editable warning leads, in minutes, separated by commas.
    @State private var leadsText = ""

    // body lays out the step strip, the step and its buttons.
    var body: some View {
        VStack(spacing: 0) {
            strip
                .padding(.top, 16)
                .padding(.horizontal, 20)
            HStack(alignment: .top, spacing: 14) {
                TugImage(name: "tug-head", outfit: Theme.dressed(store.settings))
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.title(state.step))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            buttons
                .padding(16)
        }
        .frame(width: 560, height: 600)
        .onAppear {
            leadsText = SettingsView.format(store.settings.warningLeads)
            facts = setupFacts()
        }
        .onChange(of: accounts.states) { facts = setupFacts() }
        .onChange(of: state.index) { facts = setupFacts() }
    }

    // strip shows every step's title with the current one marked.
    private var strip: some View {
        HStack(spacing: 6) {
            ForEach(Array(state.steps.enumerated()), id: \.offset) { offset, step in
                HStack(spacing: 4) {
                    Circle()
                        .fill(offset <= state.index ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(step.title)
                        .font(.system(size: 11, weight: offset == state.index ? .bold : .regular, design: .rounded))
                        .foregroundStyle(offset == state.index ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if offset < state.steps.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                }
            }
        }
    }

    // content is the body of the step showing.
    @ViewBuilder private var content: some View {
        switch state.step {
        case .access:
            accessStep
        case .connect:
            connectStep
        case .bark:
            barkStep
        case .dressUp:
            dressUpStep
        case .done:
            doneStep
        }
    }

    // accessStep says why Tug reads calendars before macOS asks.
    private var accessStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tug lives in your menu bar and barks when a meeting is about to start. To do that he reads your calendars. He only reads. Nothing leaves your Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Button("I don't use macOS Calendar") {
                store.settings.useMacCalendar = false
                onSourcesChanged()
                state.advance()
            }
            .buttonStyle(.link)
        }
    }

    // connectStep shows what Tug sees and the accounts this build can connect.
    private var connectStep: some View {
        Form {
            CalendarSourcesView(
                store: store,
                accounts: accounts,
                facts: $facts,
                setupFacts: setupFacts,
                onSourcesChanged: onSourcesChanged,
                onAllowAccess: onAllowAccess,
                kinds: AccountKind.allCases.filter { (facts ?? setupFacts()).availableKinds.contains($0) }
            )
        }
        .formStyle(.grouped)
        .padding(.horizontal, -20)
    }

    // barkStep sets working hours and warning times, with the off default spelled out so it is not missed.
    private var barkStep: some View {
        Form {
            Section {
                Text("Right now Tug barks at every meeting, evenings and weekends too. Turn this on and he stays quiet outside your hours.")
                    .fixedSize(horizontal: false, vertical: true)
                WorkingHoursFields(store: store)
            } header: {
                Text("Working hours")
            }
            Section {
                TextField(text: $leadsText, prompt: Text("10, 5")) {
                    Text("Warn at")
                    Text("Minutes before the meeting, separated by commas.")
                }
                .onChange(of: leadsText) {
                    if let leads = SettingsView.parseLeads(leadsText) {
                        store.settings.warningLeads = leads
                    }
                }
            } header: {
                Text("Warnings")
            } footer: {
                Text("You can change this any time in Settings, Hours and Alerts.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, -20)
    }

    // dressUpStep lets the user keep Tug plain before a holiday comes around.
    private var dressUpStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tug likes to dress up to celebrate from time to time: a party hat on New Year's, a vampire cape on Halloween, a Santa hat in December, and he barks a holiday tune instead of the plain bark. If you'd rather he didn't, turn it off here.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Dress Tug up for holidays", isOn: $store.settings.showOutfits)
            Toggle("Bark holiday tunes", isOn: $store.settings.holidayTunes)
            Text("Settings, Look and Sound, later.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // doneStep offers login at startup and a test alarm before closing.
    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tug is on duty. Your next meetings are in his menu.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Start Sheepdog at login", isOn: $state.startAtLogin)
                .disabled(state.needsLoginApproval)
            if state.needsLoginApproval {
                HStack {
                    Text("macOS needs you to allow Sheepdog in Login Items.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items", action: onOpenLoginItems)
                }
            }
        }
    }

    // buttons holds Back, the step's extra button and its primary button.
    private var buttons: some View {
        HStack {
            if state.canGoBack {
                Button("Back") { state.index -= 1 }
            }
            if state.step == .done {
                Button("Test the alarm", action: onTestAlarm)
            }
            Spacer()
            primary
        }
    }

    // primary is the step's main button.
    @ViewBuilder private var primary: some View {
        switch state.step {
        case .access:
            Button("Allow calendar access") {
                state.askingAccess = true
                Task {
                    _ = await onRequestAccess()
                    state.askingAccess = false
                    state.advance()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(state.askingAccess)
        case .done:
            Button(state.needsLoginApproval ? "Close" : "Done") {
                if state.needsLoginApproval {
                    onClose()
                } else if onDone(state.startAtLogin) {
                    state.needsLoginApproval = true
                } else {
                    onClose()
                }
            }
            .keyboardShortcut(.defaultAction)
        default:
            Button("Continue") { state.advance() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
