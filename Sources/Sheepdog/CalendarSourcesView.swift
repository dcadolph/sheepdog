import SwiftUI

import SheepdogCore

// CalendarSourcesView lists what Tug sees and the calendar sources, shared by Settings and the setup window.
struct CalendarSourcesView: View {
    // store holds the live settings.
    @Bindable var store: SettingsStore
    // accounts holds the calendar sign-ins.
    let accounts: Accounts
    // facts is what Tug saw when the caller last looked.
    @Binding var facts: SetupFacts?
    // setupFacts gathers what Tug sees, for the What Tug sees section.
    let setupFacts: () -> SetupFacts
    // onSourcesChanged rereads the calendars after a source is turned on or off.
    let onSourcesChanged: () -> Void
    // onAllowAccess opens Calendar privacy settings.
    let onAllowAccess: () -> Void
    // kinds lists the services that get an account row.
    let kinds: [AccountKind]
    // openURL opens System Settings at Internet Accounts.
    @Environment(\.openURL) private var openURL

    // body lays out the What Tug sees section above the Calendars section.
    var body: some View {
        whatTugSees
        Section {
            Toggle("Use calendars from macOS Calendar", isOn: $store.settings.useMacCalendar)
                .onChange(of: store.settings.useMacCalendar) {
                    onSourcesChanged()
                    facts = setupFacts()
                }
            ForEach(kinds) { kind in
                AccountRow(kind: kind, accounts: accounts)
            }
        } header: {
            Text("Calendars")
        } footer: {
            Text("Microsoft and Google sign in in your browser. iCloud needs an app-specific password from account.apple.com. Other CalDAV servers, such as Fastmail or Nextcloud, need their address and your password. Sheepdog only reads your calendars, and keeps every sign-in in your Keychain.")
                .formFooter()
        }
        .sheet(item: Binding(get: { accounts.passwordPrompt }, set: { accounts.passwordPrompt = $0 })) { kind in
            PasswordSignInSheet(kind: kind, accounts: accounts)
        }
    }

    // whatTugSees lists the macOS Calendar accounts Tug reads and the hints about missing ones.
    @ViewBuilder private var whatTugSees: some View {
        Section {
            let facts = facts ?? setupFacts()
            ForEach(Array(facts.sources.enumerated()), id: \.offset) { _, source in
                LabeledContent(Self.sourceLabel(source), value: Self.calendarCount(source.calendarCount))
            }
            if facts.sources.isEmpty && facts.macCalendarOn && facts.macCalendarAccess == .granted {
                Text("macOS Calendar has no calendars.")
                    .foregroundStyle(.secondary)
            }
            if !facts.macCalendarOn {
                Text("Tug isn't reading macOS Calendar.")
                    .foregroundStyle(.secondary)
            }
            ForEach(CalendarSetup.hints(facts), id: \.self) { hint in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hint.message)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = hint.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    if hint.action == .allowAccess {
                        Button("Allow calendar access…", action: onAllowAccess)
                            .controlSize(.small)
                    } else if hint.detail != nil {
                        Button("Open Internet Accounts") { openURL(AccountRow.internetAccounts) }
                            .controlSize(.small)
                    }
                }
            }
            Button("Check again") { self.facts = setupFacts() }
        } header: {
            Text("What Tug sees")
        } footer: {
            Text("These are the accounts in macOS Calendar. To add a work calendar, connect it below or add the account in System Settings, Internet Accounts.")
                .formFooter()
        }
    }

    // sourceLabel names a source, adding its own title when the user named it.
    private static func sourceLabel(_ source: SetupSource) -> String {
        let name: String
        switch source.kind {
        case .local:
            name = "On My Mac"
        case .icloud:
            name = "iCloud"
        case .exchange:
            name = "Exchange"
        case .google:
            name = "Google"
        case .caldav:
            name = "CalDAV"
        case .other:
            return source.title.isEmpty ? "Other" : source.title
        }
        return source.title.isEmpty || source.title == name ? name : "\(name) (\(source.title))"
    }

    // calendarCount says how many calendars a source holds.
    private static func calendarCount(_ count: Int) -> String {
        count == 1 ? "1 calendar" : "\(count) calendars"
    }
}
