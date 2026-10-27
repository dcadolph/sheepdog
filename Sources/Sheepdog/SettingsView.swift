import SwiftUI
import UniformTypeIdentifiers

import SheepdogCore

// SettingsView edits every AlertSettings field.
struct SettingsView: View {
    // store holds the live settings.
    @Bindable var store: SettingsStore
    // loginItem controls starting Sheepdog at login.
    let loginItem: LoginItem
    // accounts holds the calendar sign-ins.
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

    // body lays out the settings tabs above the buttons every tab shares.
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
                calendarsTab
                    .tabItem { Label("Calendars", systemImage: "calendar") }
                alertsTab
                    .tabItem { Label("Alerts", systemImage: "bell") }
                soundTab
                    .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
                hoursTab
                    .tabItem { Label("Hours", systemImage: "clock") }
                lookTab
                    .tabItem { Label("Look", systemImage: "paintpalette") }
            }
            .padding([.top, .horizontal])
            HStack {
                Button("Test the alarm", action: onTestAlarm)
                Spacer()
                Button("Restore defaults") {
                    store.reset()
                    leadsText = Self.format(store.settings.warningLeads)
                }
            }
            .padding()
        }
        .frame(width: 560, height: 600)
        .onAppear {
            leadsText = Self.format(store.settings.warningLeads)
            loginItem.refresh()
        }
    }

    // generalTab holds the app header, login and update options and the backup buttons.
    private var generalTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    TugImage(name: "tug", outfit: Theme.dressed(store.settings))
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sheepdog")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("Tug makes sure you get to your meetings.")
                            .foregroundStyle(.secondary)
                        Link("Contribute on GitHub…", destination: Support.repo)
                            .help(Support.contributeTip)
                            .font(.callout)
                    }
                }
            }
            Section("General") {
                Toggle("Check for updates", isOn: $store.settings.checkForUpdates)
                    .help("Once a day Sheepdog asks GitHub for the latest release. It sends no version or identifier.")
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
                Text("Saves your warnings, sounds, filters, working hours and Slack channels to a file you can import on any Mac. Sign-ins stay in your Keychain, so connect your calendars again after importing on a new Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // lookTab holds Tug's collar, the custom colors and the holiday outfit switch.
    private var lookTab: some View {
        Form {
            Section {
                HStack {
                    Picker("Tug's collar", selection: $store.settings.theme) {
                        ForEach(ThemeName.presets) { theme in
                            Text(theme == AlertSettings().theme ? "\(theme.label) (default)" : theme.label).tag(theme)
                        }
                        Divider()
                        Text(ThemeName.custom.label).tag(ThemeName.custom)
                    }
                    TugImage(name: "tug-head", palette: store.settings.palette, outfit: Theme.dressed(store.settings))
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }
                Toggle("Dress Tug up for holidays", isOn: $store.settings.showOutfits)
            } header: {
                Text("Look")
            } footer: {
                Text("The collar also colors the alarm, the countdown and the hold-my-place card. "
                    + "Around New Year's, Valentine's Day, St. Patrick's Day, Easter, Halloween, "
                    + "Thanksgiving and Christmas, Tug wears an outfit. Use Test the alarm to see it.")
                    .foregroundStyle(.secondary)
            }
            if store.settings.theme == .custom {
                customSection
            }
        }
        .formStyle(.grouped)
    }

    // customSection edits the picked colors of the Custom collar and shows which ones were adjusted.
    private var customSection: some View {
        let resolved = store.settings.customColors.resolved
        return Section {
            Picker("Start from", selection: Binding<ThemeName?>(
                get: { nil },
                set: { if let theme = $0 { store.settings.customColors = CustomColors.seeded(from: theme) } }
            )) {
                Text("Choose a collar…").tag(ThemeName?.none)
                ForEach(ThemeName.presets) { theme in
                    Text(theme.label).tag(ThemeName?.some(theme))
                }
            }
            colorRow("Background", hex: $store.settings.customColors.background,
                     adjusted: resolved.adjusted.contains(.background))
            colorRow("Ring and buttons", hex: $store.settings.customColors.accent,
                     adjusted: resolved.adjusted.contains(.accent))
            optionalColorRow("Collar", off: "Tug's own collar", hex: $store.settings.customColors.collar,
                             fallback: "#588d9c", adjusted: false)
            optionalColorRow("Already started", off: "Picked for the background", hex: $store.settings.customColors.late,
                             fallback: resolved.palette.late.hex, adjusted: resolved.adjusted.contains(.late))
        } header: {
            Text("Custom colors")
        } footer: {
            Text("Pick two to four colors and Tug works out the rest so the text stays readable. "
                + "The color panel takes a hex value or a drag around the wheel.")
                .foregroundStyle(.secondary)
        }
    }

    // colorRow is a color picker bound to a hex string, with a note when the app moved the color.
    private func colorRow(_ title: String, hex: Binding<String>, adjusted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ColorPicker(title, selection: Self.colorBinding(hex), supportsOpacity: false)
            if adjusted {
                Text("Adjusted so the text stays readable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // optionalColorRow is a color picker with a switch that leaves the color unset.
    private func optionalColorRow(
        _ title: String, off: String, hex: Binding<String?>, fallback: String, adjusted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(isOn: Binding(
                    get: { hex.wrappedValue != nil },
                    set: { hex.wrappedValue = $0 ? fallback : nil }
                )) {
                    Text(title)
                }
                .toggleStyle(.checkbox)
                Spacer()
                if hex.wrappedValue == nil {
                    Text(off)
                        .foregroundStyle(.secondary)
                } else {
                    ColorPicker("", selection: Self.colorBinding(Binding(
                        get: { hex.wrappedValue ?? fallback },
                        set: { hex.wrappedValue = $0 }
                    )), supportsOpacity: false)
                    .labelsHidden()
                }
            }
            if adjusted {
                Text("Adjusted so the text stays readable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // colorBinding converts a hex string binding to the Color binding a ColorPicker wants.
    private static func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(RGB(hex: hex.wrappedValue) ?? RGB(hex: "#0f1012")!) },
            set: { color in
                if let rgb = RGB(color) {
                    hex.wrappedValue = rgb.hex
                }
            }
        )
    }

    // calendarsTab holds the calendar sources, the Slack channels and which events alert.
    private var calendarsTab: some View {
        Form {
            Section {
                Toggle("Use calendars from macOS Calendar", isOn: $store.settings.useMacCalendar)
                    .onChange(of: store.settings.useMacCalendar) { onSourcesChanged() }
                ForEach(AccountKind.allCases) { kind in
                    AccountRow(kind: kind, accounts: accounts)
                }
            } header: {
                Text("Calendars")
            } footer: {
                Text("Microsoft and Google sign in in your browser. iCloud needs an app-specific password from account.apple.com. Other CalDAV servers, such as Fastmail or Nextcloud, need their address and your password. Sheepdog only reads your calendars, and keeps every sign-in in your Keychain.")
                    .foregroundStyle(.secondary)
            }
            .sheet(item: Binding(get: { accounts.passwordPrompt }, set: { accounts.passwordPrompt = $0 })) { kind in
                PasswordSignInSheet(kind: kind, accounts: accounts)
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
                Text("Let them know on the alarm copies a short message to your clipboard and opens the channel, so you can paste it. Use Copy link on a channel in Slack.")
                    .foregroundStyle(.secondary)
            }
            Section("Which events alert") {
                Toggle("Include tentative meetings", isOn: $store.settings.includeTentative)
                Toggle("Skip events with no other attendees", isOn: $store.settings.requireAttendees)
            }
        }
        .formStyle(.grouped)
    }

    // alertsTab holds the warnings, the takeover and snooze limits.
    private var alertsTab: some View {
        Form {
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
            }
            Section("Join") {
                joinPicker("Teams", selection: $store.settings.joinOpens.teams)
                joinPicker("Zoom", selection: $store.settings.joinOpens.zoom)
                joinPicker("Webex", selection: $store.settings.joinOpens.webex)
                joinPicker("Slack huddles", selection: $store.settings.joinOpens.slack)
                LabeledContent("Google Meet", value: "In the browser (Meet has no Mac app)")
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
        }
        .formStyle(.grouped)
    }

    // soundTab holds the warning and alarm sounds and where they play.
    private var soundTab: some View {
        Form {
            Section("Sound output") {
                soundPicker("Warning chime", selection: $store.settings.chimeSound)
                soundPicker("Alarm sound", selection: $store.settings.alarmSound)
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
            Section {
                Toggle("Bark holiday tunes", isOn: $store.settings.holidayTunes)
                if let melody = BarkMelody.current(outfit: Theme.season(), settings: store.settings) {
                    HStack {
                        Text("This week: \(melody.title)")
                        Spacer()
                        Button {
                            previewer.previewMelody(melody, settings: store.settings)
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Play this tune")
                    }
                }
            } footer: {
                Text("Around New Year's, Valentine's Day, St. Patrick's Day, Halloween, Thanksgiving and "
                    + "Christmas, Tug barks a tune for the alarm when the alarm sound is one of his barks.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // hoursTab holds the working hours.
    private var hoursTab: some View {
        Form {
            Section {
                Toggle("Only bark during working hours", isOn: $store.settings.workingHours.enabled)
                Group {
                    DatePicker("Start", selection: shiftMinutes(\.start), displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: shiftMinutes(\.end), displayedComponents: .hourAndMinute)
                    LabeledContent("Days") {
                        HStack {
                            ForEach(Self.weekdayOrder, id: \.self) { day in
                                Toggle(Calendar.current.veryShortWeekdaySymbols[day - 1], isOn: weekday(day))
                                    .toggleStyle(.checkbox)
                            }
                        }
                    }
                    Picker("Outside working hours", selection: $store.settings.workingHours.outside) {
                        ForEach(OffHours.allCases) { Text($0.label).tag($0) }
                    }
                }
                .disabled(!store.settings.workingHours.enabled)
            } header: {
                Text("Working hours")
            } footer: {
                Text("A meeting that starts inside your hours alarms in full, even when it runs past the end. An end before the start is an overnight shift, which belongs to the day it starts. Test the alarm always works.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // weekdayOrder lists Calendar weekday numbers starting from the locale's first day of the week.
    private static let weekdayOrder: [Int] = {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }()

    // shiftMinutes binds a time picker to a working hours field held in minutes after midnight.
    private func shiftMinutes(_ field: WritableKeyPath<WorkingHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = store.settings.workingHours[keyPath: field]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())
                    ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.settings.workingHours[keyPath: field] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // weekday binds a checkbox to whether a shift can start on that Calendar weekday.
    private func weekday(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { store.settings.workingHours.weekdays.contains(day) },
            set: { checked in
                var days = Set(store.settings.workingHours.weekdays)
                if checked {
                    days.insert(day)
                } else {
                    days.remove(day)
                }
                store.settings.workingHours.weekdays = days.sorted()
            }
        )
    }

    // joinPicker chooses whether one provider's meeting links open in its app or the browser.
    private func joinPicker(_ title: String, selection: Binding<JoinOpen>) -> some View {
        Picker(title, selection: selection) {
            ForEach(JoinOpen.allCases, id: \.self) { Text($0.label).tag($0) }
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
    // openURL opens the admins page and System Settings.
    @Environment(\.openURL) private var openURL

    // body lays out the label, status and button.
    var body: some View {
        let state = accounts.states[kind] ?? .notConfigured
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                    Text(Self.status(state, kind: kind))
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
                    if !kind.usesPassword {
                        Button("Cancel") { accounts.cancelSignIn(kind) }
                    }
                case .connected:
                    Button("Disconnect") { accounts.disconnect(kind) }
                case .needsSignIn:
                    Button("Sign in again…") { accounts.connect(kind) }
                    Button("Disconnect") { accounts.disconnect(kind) }
                }
            }
            if let problem = accounts.problems[kind] {
                let refusal = accounts.refusals[kind]
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(refusal == .userDeclined ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                if refusal?.needsOrganization == true {
                    HStack {
                        Button("For IT admins") { openURL(Self.adminsPage) }
                        Button("Open Internet Accounts") { openURL(Self.internetAccounts) }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // adminsPage is the site page that tells an IT admin how to approve Sheepdog.
    private static let adminsPage = URL(string: "https://macsheepdog.com/admins")!
    // internetAccounts opens System Settings at Internet Accounts.
    private static let internetAccounts = URL(
        string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
    )!

    // status describes a state in a few words.
    private static func status(_ state: AccountState, kind: AccountKind) -> String {
        switch state {
        case .notConfigured:
            return "Not available in this build"
        case .signedOut:
            return "Not connected"
        case .signingIn:
            return kind.usesPassword ? "Checking the password" : "Finish signing in in your browser"
        case .connected(let address):
            return address.map { "Connected as \($0)" } ?? "Connected"
        case .needsSignIn(let address):
            return address.map { "\($0) needs you to sign in again" } ?? "Needs you to sign in again"
        }
    }
}

// PasswordSignInSheet asks for a password service's user name and password and connects only when they work.
struct PasswordSignInSheet: View {
    // kind is the service.
    let kind: AccountKind
    // accounts checks and saves the sign-in.
    let accounts: Accounts
    // server is the typed server address, for services without a fixed one.
    @State private var server = ""
    // username is the typed user name.
    @State private var username = ""
    // password is the typed password, cleared once the check finishes.
    @State private var password = ""
    // problem is why the last attempt failed.
    @State private var problem: String?
    // checking reports an attempt in progress.
    @State private var checking = false

    // body lays out the fields, the hint and the buttons.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect \(kind.label)")
                .font(.headline)
            Form {
                if kind.server == nil {
                    TextField("Server", text: $server, prompt: Text("https://caldav.example.com"))
                        .textContentType(.URL)
                }
                TextField(Self.usernameLabel(kind), text: $username)
                    .textContentType(.username)
                SecureField(Self.passwordLabel(kind), text: $password)
                    .textContentType(.password)
            }
            .disabled(checking)
            Text(Self.hint(kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if checking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { accounts.passwordPrompt = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checking || !filled)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // filled reports whether every shown field has something in it.
    private var filled: Bool {
        let blank = { (text: String) in text.trimmingCharacters(in: .whitespaces).isEmpty }
        return !blank(username) && !password.isEmpty && (kind.server != nil || !blank(server))
    }

    // connect checks the credentials and closes the sheet when they work.
    private func connect() {
        checking = true
        problem = nil
        let address = server
        let name = username.trimmingCharacters(in: .whitespaces)
        let secret = password
        Task {
            problem = await accounts.connectPassword(kind, server: address, username: name, password: secret)
            password = ""
            checking = false
        }
    }

    // usernameLabel names the user name field.
    private static func usernameLabel(_ kind: AccountKind) -> String {
        kind == .icloud ? "Apple ID" : "User name"
    }

    // passwordLabel names the password field.
    private static func passwordLabel(_ kind: AccountKind) -> String {
        kind == .icloud ? "App-specific password" : "Password"
    }

    // hint tells the user where the password comes from.
    private static func hint(_ kind: AccountKind) -> String {
        switch kind {
        case .caldav:
            return "Use the CalDAV address your provider gives, such as https://caldav.fastmail.com. Sheepdog finds your calendars from there, only reads them, and keeps the password in your Keychain."
        case .icloud:
            return "Make an app-specific password at account.apple.com, under Sign-In and Security. Your Apple ID password will not work here. Sheepdog only reads your calendars and keeps the password in your Keychain."
        default:
            return "Sheepdog only reads your calendars and keeps the password in your Keychain."
        }
    }
}
