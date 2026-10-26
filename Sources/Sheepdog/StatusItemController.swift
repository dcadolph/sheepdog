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
        item.button?.image = Self.image(for: .idle)
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // shown is the stage the menu bar icon currently draws.
    private var shown: Stage = .idle
    // shownNap reports whether the menu bar icon currently draws the napping glyph.
    private var shownNap = false
    // shownOutfit is the outfit the menu bar icon currently draws, or nil for none.
    private var shownOutfit: Outfit?
    // shownHover is the hover text currently set on the menu bar icon.
    private var shownHover = ""

    // update refreshes the icon for the current stage and the countdown beside it.
    func update() {
        let stage = coordinator.active?.stage ?? .idle
        let napping = coordinator.isNapping() && stage == .idle
        let outfit = napping ? nil : Theme.outfit
        if stage != shown || napping != shownNap || outfit != shownOutfit {
            shown = stage
            shownNap = napping
            shownOutfit = outfit
            item.button?.image = napping
                ? (Art.napGlyph() ?? Self.image(for: stage))
                : Self.image(for: stage, outfit: outfit)
        }
        updateHover()
        guard let active = coordinator.active else {
            item.button?.title = ""
            return
        }
        item.button?.title = " " + Countdown.short(start: active.meeting.start, now: Date())
    }

    // updateHover sets the icon's hover text, only when it changes so a showing tooltip is not reset each second.
    private func updateHover() {
        let now = Date()
        let next = coordinator.meetings.first { $0.start > now && coordinator.state(for: $0).resolution == nil }
        let hover = Hover.status(
            active: coordinator.active?.meeting, next: next, napLine: napLine(), offDutyLine: offDutyLine(), now: now
        )
        if hover != shownHover {
            shownHover = hover
            item.button?.toolTip = hover
        }
    }

    // napLine says when Tug wakes, or nil while he is awake.
    private func napLine() -> String? {
        guard coordinator.isNapping(), let until = coordinator.napUntil else {
            return nil
        }
        return until == Nap.forever ? "Napping until you wake him" : "Napping until \(napTime(until))"
    }

    // offDutyLine says when working hours start again, or nil while Tug is on duty.
    private func offDutyLine() -> String? {
        let hours = coordinator.settingsStore.settings.workingHours
        let now = Date()
        guard hours.isOffDuty(now: now, calendar: .current) else {
            return nil
        }
        guard let start = hours.nextStart(after: now, calendar: .current) else {
            return "Off duty"
        }
        return "Off duty until \(shiftTime(start))"
    }

    // shiftTime renders a shift start, with the weekday when it is not today.
    private func shiftTime(_ date: Date) -> String {
        let time = timeFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) {
            return time
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    // image returns Tug's glyph for a stage, dressed in the outfit when there is one, or the system dog
    // symbol outside the app bundle.
    private static func image(for stage: Stage, outfit: Outfit? = nil) -> NSImage? {
        if let outfit, let dressed = Art.outfitGlyph(for: stage, outfit: outfit) {
            return dressed
        }
        if let glyph = Art.glyph(for: stage) {
            return glyph
        }
        let symbol = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: "Sheepdog")
        symbol?.isTemplate = true
        return symbol
    }

    // menuNeedsUpdate rebuilds the menu each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = coordinator.settingsStore.settings
        if let update = coordinator.availableUpdate {
            let version = update.tag.hasPrefix("v") ? String(update.tag.dropFirst()) : update.tag
            menu.addItem(action(
                "Sheepdog \(version) is available", #selector(openUpdate),
                tip: "Opens the release page on GitHub. Nothing installs by itself."
            ))
            menu.addItem(.separator())
        }
        if settings.useMacCalendar && coordinator.calendar.access != .granted {
            menu.addItem(action(
                "Allow calendar access…", #selector(openPrivacy),
                tip: "Opens System Settings so Tug can read your Mac calendars."
            ))
            menu.addItem(.separator())
        }
        if !settings.useMacCalendar && !coordinator.accounts.hasAccounts {
            menu.addItem(action(
                "Connect a calendar…", #selector(showSettings),
                tip: "Opens settings to connect a calendar for Tug to watch."
            ))
            menu.addItem(.separator())
        }
        for kind in AccountKind.allCases {
            if case .needsSignIn = coordinator.accounts.states[kind] {
                menu.addItem(action(
                    "Sign in to \(kind.label) again…", #selector(showSettings),
                    tip: "Tug lost access to your \(kind.label) calendar. Opens settings to sign in again."
                ))
                menu.addItem(.separator())
            }
        }
        let held = coordinator.heldPlaces
        for place in held {
            let note = place.note.count > 48 ? place.note.prefix(47) + "…" : Substring(place.note)
            let entry = action("Holding: \(note)", #selector(showHeld(_:)))
            entry.representedObject = place.id
            entry.toolTip = "From before \(place.title). Choose to see it now."
            menu.addItem(entry)
        }
        if !held.isEmpty {
            menu.addItem(.separator())
        }
        let upcoming = coordinator.meetings.filter { $0.end > Date() }
        if upcoming.isEmpty {
            menu.addItem(withTitle: "No meetings in the next 12 hours", action: nil, keyEquivalent: "")
        }
        for meeting in upcoming.prefix(Self.visibleMeetings) {
            menu.addItem(meetingRow(meeting))
        }
        if upcoming.count > Self.visibleMeetings {
            let more = NSMenu()
            for meeting in upcoming.dropFirst(Self.visibleMeetings) {
                more.addItem(meetingRow(meeting))
            }
            let entry = NSMenuItem(title: "More meetings", action: nil, keyEquivalent: "")
            entry.toolTip = "\(upcoming.count - Self.visibleMeetings) more in the next 12 hours."
            entry.submenu = more
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        addNapItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(action(
            "Test the alarm", #selector(testAlarm),
            tip: "Runs a pretend meeting through the full alarm so you can see and hear what Tug does."
        ))
        menu.addItem(action(
            "Refresh calendars", #selector(refresh), tip: "Refreshes the connection to every calendar Tug is watching."
        ))
        menu.addItem(action(
            "Settings…", #selector(showSettings), key: ",",
            tip: "Choose which calendars Tug watches, when he barks and how loud."
        ))
        menu.addItem(.separator())
        if Support.url != nil {
            menu.addItem(action("Buy Tug a treat…", #selector(openSupport), tip: Support.treatTip))
        }
        menu.addItem(action(
            "Quit Sheepdog", #selector(quit), key: "q",
            tip: "Tug stops watching your calendars until you open Sheepdog again."
        ))
    }

    // visibleMeetings is how many meetings the menu lists before the rest move under More meetings.
    private static let visibleMeetings = 4

    // meetingRow builds one meeting's menu entry with its tooltip and actions submenu.
    private func meetingRow(_ meeting: Meeting) -> NSMenuItem {
        let treatment = coordinator.settingsStore.settings.workingHours.treatment(for: meeting.start, calendar: .current)
        let mark = treatment == .full ? "" : " · after hours"
        let entry = NSMenuItem(
            title: "\(timeFormatter.string(from: meeting.start))  \(meeting.title)\(mark)", action: nil, keyEquivalent: ""
        )
        if coordinator.state(for: meeting).resolution != nil {
            entry.state = .on
            entry.toolTip = "Handled. Tug stays quiet for this one."
        } else {
            let verb = meeting.start > Date() ? "Starts" : "Started"
            var tip = "\(verb) \(Countdown.relative(start: meeting.start, now: Date()))."
            switch treatment {
            case .silent:
                tip += " After hours, so Tug stays quiet for this one."
            case .quiet:
                tip += " After hours, so Tug shows the countdown without barking."
            case .full:
                break
            }
            entry.toolTip = tip
        }
        entry.submenu = meetingMenu(meeting)
        return entry
    }

    // addNapItems adds Nap time and its lengths while Tug is awake, or the nap's end and Wake Tug while he sleeps.
    private func addNapItems(to menu: NSMenu) {
        if let line = napLine() {
            let entry = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            entry.toolTip = "Tug stays quiet for real meetings until then. Test the alarm still works."
            menu.addItem(entry)
            menu.addItem(action(
                "Wake Tug", #selector(wake),
                tip: "Ends the nap. A meeting already in its alert window alerts right away."
            ))
            return
        }
        let hours = coordinator.settingsStore.settings.workingHours
        let lengths: [(NapLength, String)] = [
            (.oneHour, "For 1 hour"),
            (.threeHours, "For 3 hours"),
            (.untilMorning, Nap.morningLabel(now: Date(), calendar: .current, hours: hours)),
            (.untilWoken, "Until I wake him"),
        ]
        let submenu = NSMenu()
        let now = Date()
        for (length, title) in lengths {
            let until = Nap.until(length, now: now, calendar: .current, hours: hours)
            let tip = until == Nap.forever ? "Tug sleeps until you choose Wake Tug." : "Tug wakes at \(napTime(until))."
            let entry = action(title, #selector(nap(_:)), tip: tip)
            entry.representedObject = length.rawValue
            submenu.addItem(entry)
        }
        let entry = NSMenuItem(title: "Nap time", action: nil, keyEquivalent: "")
        entry.toolTip = "Put Tug down for a nap. He stays quiet for real meetings until he wakes."
        entry.submenu = submenu
        menu.addItem(entry)
    }

    // napTime renders a nap's end, with the day when it is not today.
    private func napTime(_ date: Date) -> String {
        let time = timeFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) {
            return time
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "\(time) tomorrow"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // meetingMenu builds a meeting row's submenu: Join when there is a link, then Open in Calendar.
    private func meetingMenu(_ meeting: Meeting) -> NSMenu {
        let menu = NSMenu()
        if meeting.link != nil {
            let join = action(
                "Join meeting", #selector(joinMeeting(_:)), tip: "Opens the meeting link and tells Tug you joined."
            )
            join.representedObject = meeting.id
            menu.addItem(join)
        }
        let show = action(
            "Open in Calendar", #selector(openInCalendar(_:)), tip: "Shows this meeting in the calendar it came from."
        )
        show.representedObject = meeting.id
        menu.addItem(show)
        return menu
    }

    // action creates a menu item that targets this controller, with tip as its hover text.
    private func action(_ title: String, _ selector: Selector, key: String = "", tip: String? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        entry.toolTip = tip
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

    // openInCalendar shows the chosen meeting in its calendar.
    @objc private func openInCalendar(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let meeting = coordinator.meetings.first(where: { $0.id == id })
        else {
            return
        }
        coordinator.openInCalendar(meeting)
    }

    // showHeld brings back the chosen held note.
    @objc private func showHeld(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        coordinator.handBackNow(id)
    }

    // nap puts Tug to sleep for the chosen length.
    @objc private func nap(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let length = NapLength(rawValue: raw) else {
            return
        }
        coordinator.nap(length)
    }

    // wake ends Tug's nap.
    @objc private func wake() {
        coordinator.wake()
    }

    // openUpdate opens the newer release's page in the browser.
    @objc private func openUpdate() {
        if let update = coordinator.availableUpdate {
            NSWorkspace.shared.open(update.page)
        }
    }

    // openSupport opens the treat link in the browser.
    @objc private func openSupport() {
        if let url = Support.url {
            NSWorkspace.shared.open(url)
        }
    }

    // testAlarm triggers a fake takeover.
    @objc private func testAlarm() {
        coordinator.testAlarm()
    }

    // refresh rereads the calendars and the accounts.
    @objc private func refresh() {
        coordinator.refresh()
        coordinator.accounts.refresh(force: true)
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
