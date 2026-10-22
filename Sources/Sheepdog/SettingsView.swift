import SwiftUI

import SheepdogCore

// SettingsView edits every AlertSettings field.
struct SettingsView: View {
    // store holds the live settings.
    @Bindable var store: SettingsStore
    // loginItem controls starting Sheepdog at login.
    let loginItem: LoginItem
    // accounts holds the Microsoft and Google sign-ins.
    let accounts: Accounts
    // onSourcesChanged rereads the calendars after a source is turned on or off.
    let onSourcesChanged: () -> Void
    // onTestAlarm runs a full takeover with a fake meeting.
    let onTestAlarm: () -> Void
    // leadsText is the editable warning leads, in minutes, separated by commas.
    @State private var leadsText = ""

    // sounds lists the built-in alert sounds for the pickers.
    private let sounds = SoundPlayer.availableSounds()

    // body lays out the settings form.
    var body: some View {
        Form {
            Section("General") {
                Toggle("Start Sheepdog at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.needsApproval {
                    HStack {
                        Text("macOS needs you to allow Sheepdog in Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    Text("Couldn't change the login item: \(error)")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Use calendars from macOS Calendar", isOn: $store.settings.useMacCalendar)
                    .onChange(of: store.settings.useMacCalendar) { onSourcesChanged() }
                ForEach(AccountKind.allCases) { kind in
                    AccountRow(kind: kind, accounts: accounts)
                }
            } header: {
                Text("Calendars")
            } footer: {
                Text("Sign-in happens in your browser. Sheepdog only reads your calendars, and keeps the sign-in in your Keychain.")
                    .foregroundStyle(.secondary)
            }
            Section("Warnings") {
                TextField("Warn at (minutes before, comma separated)", text: $leadsText)
                    .onSubmit(applyLeads)
                    .onChange(of: leadsText) { applyLeads() }
                Toggle("Show the floating countdown", isOn: $store.settings.showPill)
                Picker("Warning chime", selection: $store.settings.chimeSound) {
                    ForEach(sounds, id: \.self) { Text($0) }
                }
            }
            Section("Takeover") {
                Stepper(
                    "Full-screen alarm \(Int(store.settings.takeoverLead)) sec before start",
                    value: $store.settings.takeoverLead,
                    in: 0...600,
                    step: 15
                )
                Stepper(
                    "Keep at you for \(Int(store.settings.nagWindow / 60)) min after start",
                    value: $store.settings.nagWindow,
                    in: 60...3600,
                    step: 60
                )
                Picker("Alarm sound", selection: $store.settings.alarmSound) {
                    ForEach(sounds, id: \.self) { Text($0) }
                }
            }
            Section("Snooze") {
                Stepper("Snoozes per meeting: \(store.settings.maxSnoozes)", value: $store.settings.maxSnoozes, in: 0...10)
                Stepper(
                    "Before start: \(Int(store.settings.snoozeBeforeStart)) sec",
                    value: $store.settings.snoozeBeforeStart,
                    in: 15...300,
                    step: 15
                )
                Stepper(
                    "After start: \(Int(store.settings.snoozeAfterStart)) sec",
                    value: $store.settings.snoozeAfterStart,
                    in: 15...300,
                    step: 15
                )
            }
            Section("Sound output") {
                Picker("Play alerts on", selection: $store.settings.alarmOutput) {
                    ForEach(AlarmOutput.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Unmute and raise volume during the alarm", isOn: $store.settings.boostVolume)
                if store.settings.boostVolume {
                    Slider(value: $store.settings.boostLevel, in: 0.2...1) {
                        Text("At least \(Int(store.settings.boostLevel * 100))%")
                    }
                }
            }
            Section("Which events alert") {
                Toggle("Include tentative meetings", isOn: $store.settings.includeTentative)
                Toggle("Skip events with no other attendees", isOn: $store.settings.requireAttendees)
            }
            Section {
                HStack {
                    Button("Test the alarm", action: onTestAlarm)
                    Spacer()
                    Button("Restore defaults") {
                        store.reset()
                        leadsText = Self.format(store.settings.warningLeads)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear {
            leadsText = Self.format(store.settings.warningLeads)
            loginItem.refresh()
        }
    }

    // applyLeads parses the leads text and saves it when every value is a valid minute count.
    private func applyLeads() {
        let parts = leadsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let minutes = parts.compactMap(Double.init)
        guard minutes.count == parts.count, minutes.allSatisfy({ $0 > 0 && $0 <= 120 }) else {
            return
        }
        store.settings.warningLeads = minutes.map { $0 * 60 }.sorted(by: >)
    }

    // format renders leads in seconds as a comma separated minute list.
    private static func format(_ leads: [TimeInterval]) -> String {
        leads.map { lead in
            let minutes = lead / 60
            return minutes == minutes.rounded() ? String(Int(minutes)) : String(minutes)
        }.joined(separator: ", ")
    }
}

// AccountRow shows one service's sign-in state with the button that changes it.
struct AccountRow: View {
    // kind is the service.
    let kind: AccountKind
    // accounts holds the sign-ins.
    let accounts: Accounts

    // body lays out the label, status and button.
    var body: some View {
        let state = accounts.states[kind] ?? .notConfigured
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                    Text(Self.status(state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                switch state {
                case .notConfigured:
                    EmptyView()
                case .signedOut:
                    Button("Connect…") { accounts.connect(kind) }
                case .signingIn:
                    ProgressView().controlSize(.small)
                    Button("Cancel") { accounts.cancelSignIn(kind) }
                case .connected:
                    Button("Disconnect") { accounts.disconnect(kind) }
                case .needsSignIn:
                    Button("Sign in again…") { accounts.connect(kind) }
                    Button("Disconnect") { accounts.disconnect(kind) }
                }
            }
            if let problem = accounts.problems[kind] {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // status describes a state in a few words.
    private static func status(_ state: AccountState) -> String {
        switch state {
        case .notConfigured:
            return "Not available in this build"
        case .signedOut:
            return "Not connected"
        case .signingIn:
            return "Finish signing in in your browser"
        case .connected(let address):
            return address.map { "Connected as \($0)" } ?? "Connected"
        case .needsSignIn(let address):
            return address.map { "\($0) needs you to sign in again" } ?? "Needs you to sign in again"
        }
    }
}
