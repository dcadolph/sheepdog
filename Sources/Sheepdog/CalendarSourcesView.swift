import AppKit
import Combine
import EventKit
import SwiftUI

import SheepdogCore

// CalendarSourcesView lists the calendars Tug reads through Apple Calendar and the direct sign-ins, shared
// by Settings and the setup window.
struct CalendarSourcesView: View {
    // store holds the live settings.
    @Bindable var store: SettingsStore
    // accounts holds the calendar sign-ins.
    let accounts: Accounts
    // facts is what Tug saw when the caller last looked.
    @Binding var facts: SetupFacts?
    // setupFacts gathers what Tug sees, for the Connected through Apple Calendar section.
    let setupFacts: () -> SetupFacts
    // onSourcesChanged rereads the calendars after a source is turned on or off.
    let onSourcesChanged: () -> Void
    // onAllowAccess opens Calendar privacy settings.
    let onAllowAccess: () -> Void
    // kinds lists the services that get an account row.
    let kinds: [AccountKind]
    // openURL opens System Settings at Internet Accounts.
    @Environment(\.openURL) private var openURL
    // expanded holds the titles of the sources whose calendar list is open.
    @State private var expanded: Set<String> = []

    // body lays out the Apple Calendar section above the direct sign-ins.
    var body: some View {
        appleCalendar
        Section {
            let covered = CalendarSetup.readThroughApple(facts ?? setupFacts())
            ForEach(kinds) { kind in
                AccountRow(kind: kind, accounts: accounts, throughApple: covered.contains(kind))
            }
        } header: {
            Text("Direct sign-in (optional)")
        } footer: {
            Text("Microsoft and Google sign in in your browser. iCloud needs an app-specific password from account.apple.com. Other CalDAV servers, such as Fastmail or Nextcloud, need their address and your password. Sheepdog only reads your calendars, and keeps every sign-in in your Keychain.")
                .formFooter()
        }
        .sheet(item: Binding(get: { accounts.passwordPrompt }, set: { accounts.passwordPrompt = $0 })) { kind in
            PasswordSignInSheet(kind: kind, accounts: accounts)
        }
    }

    // appleCalendar holds the macOS Calendar switch, the accounts Tug reads through it and the hints about
    // missing ones. It rereads them when macOS Calendar changes or Sheepdog comes to the front, so an
    // account added in Internet Accounts shows without a manual check.
    private var appleCalendar: some View {
        Section {
            Toggle("Use calendars from Apple Calendar", isOn: $store.settings.useMacCalendar)
                .onChange(of: store.settings.useMacCalendar) {
                    onSourcesChanged()
                    facts = setupFacts()
                }
            let seen = facts ?? setupFacts()
            ForEach(Array(seen.sources.enumerated()), id: \.offset) { _, source in
                sourceRow(source)
            }
            if seen.sources.isEmpty && seen.macCalendarOn && seen.macCalendarAccess == .granted {
                Text("Apple Calendar has no calendars.")
                    .foregroundStyle(.secondary)
            }
            if !seen.macCalendarOn {
                Text("Tug isn't reading Apple Calendar.")
                    .foregroundStyle(.secondary)
            }
            ForEach(CalendarSetup.hints(seen), id: \.self) { hint in
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
        } header: {
            Text("Connected through Apple Calendar")
        } footer: {
            Text("These are the accounts in Apple Calendar. To add a work calendar, connect it below or add the account in System Settings, Internet Accounts.")
                .formFooter()
        }
        .onReceive(Self.calendarChanges) { _ in
            facts = setupFacts()
        }
    }

    // sourceRow shows a source with how many of its calendars Tug reads, and opens to a checkbox per
    // calendar. The row is a plain button because a DisclosureGroup's triangle in a grouped form has no
    // press action for VoiceOver. A source without a calendar list, such as one in an offscreen render,
    // shows the count.
    @ViewBuilder
    private func sourceRow(_ source: SetupSource) -> some View {
        let hidden = source.calendars.filter { store.settings.hiddenCalendarIDs.contains($0.id) }.count
        let summary = CalendarChoice.summary(total: source.calendarCount, hidden: hidden)
        if source.calendars.isEmpty {
            LabeledContent(Self.sourceLabel(source), value: summary)
        } else {
            let open = expanded.contains(source.title)
            Button {
                if open {
                    expanded.remove(source.title)
                } else {
                    expanded.insert(source.title)
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(Self.sourceLabel(source))
                    Spacer()
                    Text(summary)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Self.sourceLabel(source)), \(summary)")
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open {
                ForEach(source.calendars, id: \.id) { calendar in
                    Toggle(calendar.title, isOn: shown(calendar.id))
                        .toggleStyle(.checkbox)
                        .padding(.leading, 20)
                }
            }
        }
    }

    // shown binds a checkbox to whether a calendar is left off the hidden list, and rereads the calendars
    // when it changes so the meeting list follows at once.
    private func shown(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !store.settings.hiddenCalendarIDs.contains(id) },
            set: { on in
                if on {
                    store.settings.hiddenCalendarIDs.remove(id)
                } else {
                    store.settings.hiddenCalendarIDs.insert(id)
                }
                onSourcesChanged()
            }
        )
    }

    // calendarChanges fires on the main queue when macOS Calendar's store changes or Sheepdog becomes active,
    // once per burst of changes.
    private static let calendarChanges: AnyPublisher<Notification, Never> = NotificationCenter.default
        .publisher(for: .EKEventStoreChanged)
        .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .eraseToAnyPublisher()

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
}
