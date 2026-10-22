import AppKit

import SheepdogCore

// StatusItemController owns the menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    // coordinator supplies meetings and actions.
    private let coordinator: Coordinator
    // openSettings shows the settings window.
    private let openSettings: () -> Void
    // item is the menu bar status item.
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // timeFormatter renders meeting start times in the menu.
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    // init builds the status item.
    init(coordinator: Coordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        super.init()
        let image = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: "Sheepdog")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // update refreshes the countdown beside the icon.
    func update() {
        guard let active = coordinator.active else {
            item.button?.title = ""
            return
        }
        item.button?.title = " " + Countdown.short(start: active.meeting.start, now: Date())
    }

    // menuNeedsUpdate rebuilds the menu each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if coordinator.calendar.access != .granted {
            menu.addItem(action("Allow calendar access…", #selector(openPrivacy)))
            menu.addItem(.separator())
        }
        let upcoming = coordinator.meetings.filter { $0.end > Date() }.prefix(6)
        if upcoming.isEmpty {
            menu.addItem(withTitle: "No meetings in the next 12 hours", action: nil, keyEquivalent: "")
        }
        for meeting in upcoming {
            let entry = action("\(timeFormatter.string(from: meeting.start))  \(meeting.title)", #selector(joinMeeting(_:)))
            entry.representedObject = meeting.id
            if coordinator.state(for: meeting).resolution != nil {
                entry.state = .on
            }
            if meeting.link == nil {
                entry.action = nil
            }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(action("Test the alarm", #selector(testAlarm)))
        menu.addItem(action("Refresh calendars", #selector(refresh)))
        menu.addItem(action("Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(action("Quit Sheepdog", #selector(quit), key: "q"))
    }

    // action creates a menu item that targets this controller.
    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // joinMeeting opens the chosen meeting's link and marks it joined.
    @objc private func joinMeeting(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let meeting = coordinator.meetings.first(where: { $0.id == id })
        else {
            return
        }
        coordinator.open(meeting)
        coordinator.resolve(meeting, .joined)
    }

    // testAlarm triggers a fake takeover.
    @objc private func testAlarm() {
        coordinator.testAlarm()
    }

    // refresh rereads the calendars.
    @objc private func refresh() {
        coordinator.refresh()
    }

    // showSettings opens the settings window.
    @objc private func showSettings() {
        openSettings()
    }

    // openPrivacy opens the calendar privacy pane in System Settings.
    @objc private func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // quit exits the app.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
