import AppKit

import SheepdogCore

// StatusItemController owns the menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    // coordinator supplies meetings and actions.
    private let coordinator: Coordinator
    // openSettings shows the settings window on a tab, or on the last one shown when nil.
    private let openSettings: (SettingsTab?) -> Void
    // onSetUp opens the "Set up Sheepdog" window.
    var onSetUp: (() -> Void)?
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
    init(coordinator: Coordinator, openSettings: @escaping (SettingsTab?) -> Void) {
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
    // shownHover is the hover text currently set on the menu bar icon.
    private var shownHover = ""
    // tugStage plays Tug's nap, wake or quit animation, nil when none is playing.
    private var tugStage: TugStage?
    // drawn reports whether update has run once, so the state found at launch is shown without an
    // animation.
    private var drawn = false
    // napPose is the drawing Tug naps in: dozing just after he lies down, lying once he settles.
    private var napPose = TugShape.lying
    // napTimer settles Tug after he lies down and later has him look up now and then, nil while awake.
    private var napTimer: Timer?

    // update refreshes the icon for the current stage and the countdown beside it.
    func update() {
        let stage = coordinator.active?.stage ?? .idle
        let napping = coordinator.isNapping() && stage == .idle
        if tugStage == nil, stage != shown || napping != shownNap {
            let woke = drawn && shownNap && !napping && stage == .idle
            let fell = drawn && !shownNap && napping
            shown = stage
            shownNap = napping
            if fell {
                napPose = .dozing
            }
            let image = napping
                ? (Art.napGlyph(napPose) ?? Self.image(for: stage)) : Self.image(for: stage)
            if !napping {
                napTimer?.invalidate()
                napTimer = nil
                napPose = .lying
            }
            if woke, let image {
                playChange(
                    TugMotion.wake, seconds: TugMotion.wakeSeconds, from: .lying, to: .sitting, image: image,
                    jump: TugFigure.wake
                )
            } else if fell, let image {
                playChange(
                    TugMotion.nap, seconds: TugMotion.napSeconds, from: .sitting, to: .dozing, image: image,
                    jump: .zero
                ) { [weak self] in
                    self?.scheduleNapStep(after: 1.5)
                }
            } else {
                item.button?.image = image
                if napping, napTimer == nil {
                    scheduleNapStep(after: Self.lookDelay())
                }
            }
        }
        if !drawn {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.greetDelay) { [weak self] in
                MainActor.assumeIsolated { self?.greet() }
            }
        }
        drawn = true
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

    // image returns Tug's plain glyph for a stage, or the system dog symbol outside the app bundle. Outfits
    // stay off the menu bar, where a prop at 18pt reads as clutter.
    private static func image(for stage: Stage) -> NSImage? {
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
                "Connect a calendar…", #selector(showCalendars),
                tip: "Opens settings to connect a calendar for Tug to watch."
            ))
            menu.addItem(.separator())
        }
        for kind in AccountKind.allCases {
            if case .needsSignIn = coordinator.accounts.states[kind] {
                menu.addItem(action(
                    "Sign in to \(kind.label) again…", #selector(showCalendars),
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
            "Check for Updates…", #selector(checkForUpdates),
            tip: "Asks GitHub now whether a newer Sheepdog is out."
        ))
        menu.addItem(action(
            "Set up Sheepdog…", #selector(showSetup),
            tip: "Shows which calendars Tug sees, helps you connect the ones he doesn't, and sets when he barks."
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

    // checkForUpdates asks GitHub for a newer release right away.
    @objc private func checkForUpdates() {
        coordinator.checkForUpdateNow()
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
        openSettings(nil)
    }

    // showCalendars opens the settings window on the Calendars tab.
    @objc private func showCalendars() {
        openSettings(.calendars)
    }

    // showSetup opens the "Set up Sheepdog" window.
    @objc private func showSetup() {
        onSetUp?()
    }

    // openPrivacy opens the calendar privacy pane in System Settings.
    @objc private func openPrivacy() {
        Self.openCalendarPrivacy()
    }

    // openCalendarPrivacy opens the calendar privacy pane in System Settings.
    static func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // quit has Tug bow and leap out of the menu bar, then exits the app. A napping Tug springs from
    // his nap straight into the bow. An animation still playing, or Reduce Motion, skips it.
    @objc private func quit() {
        guard tugStage == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let button = item.button, let image = button.image, let frame = button.window?.frame,
              let rect = Self.imageRect(of: button)
        else {
            NSApp.terminate(nil)
            return
        }
        var drawings = [TugShape.sitting: TugDrawing(image: image, rect: rect)]
        for shape in [TugShape.bow, .leap] {
            if let pose = Art.poseGlyph(shape) {
                drawings[shape] = TugDrawing(image: pose, rect: CGRect(origin: rect.origin, size: pose.size))
            }
        }
        let figure = TugFigure(drawings: drawings, wags: false, jump: TugFigure.exit)
        button.image = Self.blank(image.size)
        let stage = TugStage()
        tugStage = stage
        stage.play(
            TugMotion.exit, seconds: TugMotion.exitSeconds, over: frame, figure: figure,
            appearance: button.effectiveAppearance
        ) {
            NSApp.terminate(nil)
        }
    }

    // playChange animates Tug in place from the drawing the icon shows, as shape from, into image, as
    // shape to, keeping his head where it is, then sets image and runs then. Any drawing in extra is
    // placed like image. Reduce Motion, or an icon not on screen, sets image at once.
    private func playChange(
        _ motion: @escaping @Sendable (Double) -> TugPose, seconds: Double, from: TugShape, to: TugShape,
        image: NSImage, extra: [TugShape: NSImage] = [:], jump: CGVector, then: (() -> Void)? = nil
    ) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let button = item.button, let shown = button.image, let frame = button.window?.frame,
              let shownRect = Self.imageRect(of: button)
        else {
            item.button?.image = image
            then?()
            return
        }
        let place = { (drawing: NSImage) in
            TugDrawing(image: drawing, rect: CGRect(
                x: shownRect.maxX - drawing.size.width, y: shownRect.midY - drawing.size.height / 2,
                width: drawing.size.width, height: drawing.size.height
            ))
        }
        var drawings = extra.mapValues(place)
        drawings[from] = TugDrawing(image: shown, rect: shownRect)
        drawings[to] = place(image)
        let figure = TugFigure(drawings: drawings, wags: to == .sitting, jump: jump)
        button.image = Self.blank(shown.size)
        let stage = TugStage()
        tugStage = stage
        stage.play(
            motion, seconds: seconds, over: frame, figure: figure, appearance: button.effectiveAppearance
        ) { [weak self] in
            self?.tugStage = nil
            self?.item.button?.image = image
            self?.update()
            then?()
        }
    }

    // greetDelay is how long after launch Tug barks, so the menu bar has placed his icon first.
    private static let greetDelay: TimeInterval = 0.8

    // greet has Tug bark twice where he sits, once Sheepdog has opened. It does nothing if he has since
    // started napping, a meeting is showing, or another animation plays.
    private func greet() {
        guard tugStage == nil, shown == .idle, !shownNap, let image = item.button?.image else {
            return
        }
        playChange(
            TugMotion.greet, seconds: TugMotion.greetSeconds, from: .sitting, to: .sitting, image: image,
            jump: .zero
        )
    }

    // lookDelay is how long Tug naps before he next looks up, a few minutes, varied so it never feels
    // like a clock.
    private static func lookDelay() -> TimeInterval {
        .random(in: 240...540)
    }

    // scheduleNapStep runs napStep after delay, replacing any step already waiting.
    private func scheduleNapStep(after delay: TimeInterval) {
        napTimer?.invalidate()
        napTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.napStep() }
        }
    }

    // napStep settles a dozing Tug onto his paws, or has a settled Tug look up once, then schedules the
    // next look up. It does nothing once he is awake, and waits while another animation plays.
    private func napStep() {
        napTimer = nil
        guard shownNap, coordinator.isNapping() else {
            return
        }
        guard tugStage == nil else {
            scheduleNapStep(after: 5)
            return
        }
        let next: () -> Void = { [weak self] in
            self?.scheduleNapStep(after: Self.lookDelay())
        }
        guard let lying = Art.napGlyph(.lying), let dozing = Art.napGlyph(.dozing) else {
            return
        }
        if napPose == .dozing {
            napPose = .lying
            playChange(
                TugMotion.settle, seconds: TugMotion.settleSeconds, from: .dozing, to: .lying, image: lying,
                jump: .zero, then: next
            )
        } else if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            playChange(
                TugMotion.lookUp, seconds: TugMotion.lookSeconds, from: .lying, to: .lying, image: lying,
                extra: [.dozing: dozing], jump: .zero, then: next
            )
        } else {
            next()
        }
    }

    // imageRect returns where the button draws its image, on screen.
    private static func imageRect(of button: NSStatusBarButton) -> CGRect? {
        guard let cell = button.cell, let window = button.window else {
            return nil
        }
        return window.convertToScreen(button.convert(cell.imageRect(forBounds: button.bounds), to: nil))
    }

    // blank returns an empty image of size, which holds the icon's place while Tug is animated.
    private static func blank(_ size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.accessibilityDescription = "Sheepdog"
        return image
    }
}
