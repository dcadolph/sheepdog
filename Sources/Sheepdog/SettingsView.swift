import SwiftUI
import UniformTypeIdentifiers

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
    // backupError is the last export or import failure, shown under the backup buttons.
    @State private var backupError: String?

    // sounds lists the built-in alert sounds for the pickers.
    private let sounds = SoundPlayer.availableSounds()
    // previewer plays a picked sound so it can be heard before choosing it.
    @State private var previewer = SoundPlayer()

    // body lays out the settings form.
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    TugImage(name: "tug")
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sheepdog")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("Tug makes sure you get to your meetings.")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            if let support = Support.url {
                                Link("Buy Tug a treat…", destination: support)
                                    .help(Support.treatTip)
                            }
                            Link("Contribute on GitHub…", destination: Support.repo)
                                .help(Support.contributeTip)
                        }
                        .font(.callout)
                    }
                }
            }
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
            Section {
                ForEach($store.settings.slackChannels) { $channel in
                    let id = channel.id
                    SlackChannelRow(channel: $channel) {
                        store.settings.slackChannels.removeAll { $0.id == id }
                    }
                }
                Button("Add channel") {
                    store.settings.slackChannels.append(SlackChannel(name: "", link: ""))
                }
            } header: {
                Text("Slack")
            } footer: {
                Text("Msg team on the alarm copies a short message to your clipboard and opens the channel, so you can paste it. Use Copy link on a channel in Slack.")
                    .foregroundStyle(.secondary)
            }
            Section("Warnings") {
                TextField(text: $leadsText, prompt: Text("10, 5")) {
                    Text("Warn at")
                    Text("Minutes before the meeting, separated by commas.")
                }
                    .onSubmit(applyLeads)
                    .onChange(of: leadsText) { applyLeads() }
                Toggle("Show the floating countdown", isOn: $store.settings.showPill)
                Toggle("Ask what I was in the middle of", isOn: $store.settings.holdPlace)
                    .help("Tug hands the note back after the meeting.")
                soundPicker("Warning chime", selection: $store.settings.chimeSound)
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
                soundPicker("Alarm sound", selection: $store.settings.alarmSound)
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
                Picker("Theme", selection: $store.settings.theme) {
                    ForEach(ThemeName.allCases) { theme in
                        Text(theme == AlertSettings().theme ? "\(theme.label) (default)" : theme.label).tag(theme)
                    }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Colors the alarm, the countdown and the hold-my-place card. Use Test the alarm to see it.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Export settings…", action: exportSettings)
                    Button("Import settings…", action: importSettings)
                }
                if let backupError {
                    Text(backupError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves your warnings, sounds, filters and Slack channels to a file you can import on any Mac. Sign-ins stay in your Keychain, so connect your calendars again after importing on a new Mac.")
                    .foregroundStyle(.secondary)
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
        .frame(width: 520, height: 680)
        .onAppear {
            leadsText = Self.format(store.settings.warningLeads)
            loginItem.refresh()
        }
    }

    // soundPicker offers Tug's barks above the macOS sounds, with a button to hear the pick.
    private func soundPicker(_ title: String, selection: Binding<String>) -> some View {
        HStack {
            Picker(title, selection: selection) {
                Section("Tug") {
                    ForEach(TugSound.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Section("macOS") {
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
            }
            Button {
                previewer.preview(sound: selection.wrappedValue, settings: store.settings)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Play this sound")
        }
    }

    // exportSettings saves the current settings to a file the user picks.
    private func exportSettings() {
        backupError = nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SettingsBackup.fileName
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try SettingsBackup.encode(store.settings, exported: Date()).write(to: url, options: .atomic)
        } catch {
            backupError = "Couldn't save the file: \(error.localizedDescription)"
        }
    }

    // importSettings replaces every setting with the ones in a file the user picks.
    private func importSettings() {
        backupError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            store.settings = try SettingsBackup.decode(Data(contentsOf: url))
            leadsText = Self.format(store.settings.warningLeads)
            onSourcesChanged()
        } catch BackupError.notSheepdog(let app) {
            backupError = "That file is a backup from \(app), not Sheepdog."
        } catch BackupError.newerVersion {
            backupError = "That file is from a newer Sheepdog. Update Sheepdog, then import it."
        } catch {
            backupError = "That file isn't a Sheepdog settings backup."
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

// SlackChannelRow edits one Slack channel and flags a link that is not a channel link.
struct SlackChannelRow: View {
    // channel is the row being edited.
    @Binding var channel: SlackChannel
    // onRemove deletes the row.
    let onRemove: () -> Void

    // body lays out the name and link fields with a remove button.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Name", text: $channel.name, prompt: Text("#team"))
                    .frame(width: 120)
                TextField("Link", text: $channel.link, prompt: Text("https://yourteam.slack.com/archives/C0123ABCD"))
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this channel")
            }
            .labelsHidden()
            if !channel.link.isEmpty && channel.channelLink == nil {
                Text("That isn't a Slack channel link. Use Copy link on the channel in Slack.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
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
