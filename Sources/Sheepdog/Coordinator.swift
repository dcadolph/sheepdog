import AppKit
import Foundation
import os

import SheepdogCore

// Coordinator runs the once-a-second loop that turns calendar state into alerts.
@MainActor
final class Coordinator {
    // settingsStore holds the live settings.
    let settingsStore: SettingsStore
    // calendar supplies upcoming events from macOS Calendar.
    let calendar = CalendarProvider()
    // accounts supplies upcoming events from Microsoft and Google sign-ins.
    let accounts: Accounts
    // onTick is called after every tick so the menu bar can update.
    var onTick: (() -> Void)?

    // model is shared by the alert views.
    private let model = AlertModel()
    // windows shows and hides the alert surfaces.
    private let windows: AlertWindows
    // sounds plays chimes and the alarm.
    private let sounds = SoundPlayer()
    // mic watches for the user joining a call.
    private let mic = MicMonitor()
    // places holds what the user was in the middle of, per meeting.
    private let places = HeldPlaceStore()
    // draftMeeting is the meeting the note being typed belongs to.
    private var draftMeeting: Meeting?
    // focusPlaceID is the held note the user asked to see from the menu, shown ahead of the queue.
    private var focusPlaceID: String?
    // meetings are the upcoming meetings from the calendar.
    private(set) var meetings: [Meeting] = []
    // testMeetings are fake meetings created by Test the alarm.
    private var testMeetings: [Meeting] = []
    // silentTests holds the ids of test meetings made during a nap, which alarm without sound.
    private var silentTests: Set<String> = []
    // states records what the user did per meeting id.
    private var states: [String: MeetingState] = [:]
    // lastTick is when the previous tick ran, for detecting warning crossings.
    private var lastTick = Date()
    // requestingAccess reports a macOS Calendar permission prompt in progress.
    private var requestingAccess = false
    // lastRefresh is when the calendar was last read.
    private var lastRefresh = Date.distantPast
    // timer drives the tick loop.
    private var timer: Timer?
    // active is the meeting currently being alerted for, if any.
    private(set) var active: (meeting: Meeting, stage: Stage)?
    // napUntil is when Tug wakes from a nap, or nil while he is awake. It is kept in user defaults so a
    // nap survives a restart.
    private(set) var napUntil: Date? = UserDefaults.standard.object(forKey: Coordinator.napKey) as? Date
    // napKey is the user defaults key holding the nap's end.
    private static let napKey = "napUntil"
    // log records update check failures.
    private let log = Logger(subsystem: "com.dcadolph.sheepdog", category: "updates")
    // launched is when the app started, so the first update check waits out the login.
    private let launched = Date()
    // checkingUpdate reports an update check in flight.
    private var checkingUpdate = false
    // updateCheckedKey is the user defaults key holding when the last update check ran.
    private static let updateCheckedKey = "updateCheckedAt"
    // updateTagKey is the user defaults key holding the newest release tag the last check found.
    private static let updateTagKey = "updateLatestTag"
    // updatePageKey is the user defaults key holding that release's page.
    private static let updatePageKey = "updateLatestPage"
    // nudgeKey is the user defaults key holding the update card's schedule.
    private static let nudgeKey = "updateNudge"
    // nudge is when the update card last showed and whether its version was skipped. It is not part
    // of the settings backup.
    private var nudge: UpdateNudge = UserDefaults.standard.data(forKey: Coordinator.nudgeKey)
        .flatMap { try? JSONDecoder().decode(UpdateNudge.self, from: $0) } ?? UpdateNudge()
    // updateCardOpen reports that the update card was shown and not yet answered. A blocked card hides
    // and comes back when the way is clear.
    private var updateCardOpen = false
    // updater installs the update when the user presses Update now.
    private let updater = Updater()
    // fromHomebrew reports that Homebrew manages this install.
    private static let fromHomebrew = Install.homebrew { FileManager.default.fileExists(atPath: $0) }
    // runningVersion is this build's version, or nil outside the app bundle.
    private static let runningVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String).flatMap(ReleaseVersion.init)
    // slackBundleID identifies the Slack desktop app.
    private static let slackBundleID = "com.tinyspeck.slackmacgap"

    // availableUpdate is the newer release the last check found, or nil when there is none or checks are off.
    var availableUpdate: ReleaseInfo? {
        let defaults = UserDefaults.standard
        guard settings.checkForUpdates, let current = Self.runningVersion,
            let tag = defaults.string(forKey: Self.updateTagKey), let version = ReleaseVersion(tag), version > current,
            let page = defaults.string(forKey: Self.updatePageKey).flatMap(URL.init(string:)),
            page.scheme == "https", page.host == "github.com"
        else {
            return nil
        }
        return ReleaseInfo(tag: tag, page: page)
    }

    // settings is a shortcut to the live settings.
    private var settings: AlertSettings { settingsStore.settings }

    // init wires the model actions and monitors.
    init(settingsStore: SettingsStore, accounts: Accounts) {
        self.settingsStore = settingsStore
        self.accounts = accounts
        windows = AlertWindows(model: model)
        model.onJoin = { [weak self] in self?.join() }
        model.onSnooze = { [weak self] in self?.snooze() }
        model.onSkip = { [weak self] in self?.resolveActive(.skipped) }
        model.onCloseTakeover = { [weak self] in self?.closeTakeover() }
        model.onClosePill = { [weak self] in self?.hidePill() }
        model.onSaveNote = { [weak self] in self?.saveNote() }
        model.onHoldPlace = { [weak self] in self?.holdPlace() }
        model.onCancelNote = { [weak self] in self?.cancelNote() }
        model.onMsgTeam = { [weak self] in self?.toggleTeamRow() }
        model.onSendTeamMessage = { [weak self] in self?.sendTeamMessage($0) }
        model.onCopyHandBack = { [weak self] in self?.copyHandBack() }
        model.onDoneHandBack = { [weak self] in self?.doneHandBack() }
        model.onClearHandBacks = { [weak self] in self?.clearHandBacks() }
        model.onOpenUpdate = { [weak self] in self?.openUpdate() }
        model.onRemindUpdate = { [weak self] in self?.closeUpdateCard() }
        model.onSkipUpdate = { [weak self] in self?.skipUpdate() }
        model.updateCanInstall = Updater.canUpdate
        calendar.onChange = { [weak self] in self?.refresh() }
        accounts.onChange = { [weak self] in self?.refresh() }
        mic.onStart = { [weak self] in self?.micStarted() }
    }

    // start asks for calendar access when macOS Calendar is in use, reads the accounts and begins ticking.
    func start() {
        mic.start()
        requestCalendarAccessIfNeeded()
        accounts.refresh(force: true)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // checkForUpdateIfDue asks GitHub for the latest release when a check is due. The time is recorded before
    // the request, so a failure waits for the next day instead of retrying every tick.
    private func checkForUpdateIfDue(now: Date) {
        let defaults = UserDefaults.standard
        guard settings.checkForUpdates, !checkingUpdate, let current = Self.runningVersion,
            UpdateSchedule.isDue(
                lastChecked: defaults.object(forKey: Self.updateCheckedKey) as? Date, launched: launched, now: now
            )
        else {
            return
        }
        defaults.set(now, forKey: Self.updateCheckedKey)
        checkingUpdate = true
        Task { [weak self] in
            let checker = UpdateChecker(client: URLSessionClient(), current: current)
            do {
                let found = try await checker.check()
                self?.finishUpdateCheck(found)
            } catch {
                self?.finishUpdateCheck(nil, failure: error)
            }
        }
    }

    // checkForUpdateNow asks GitHub for the latest release at once, whatever the schedule or the automatic
    // check setting says, and answers in a dialog.
    func checkForUpdateNow() {
        guard !checkingUpdate, let current = Self.runningVersion else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: Self.updateCheckedKey)
        checkingUpdate = true
        Task { [weak self] in
            let checker = UpdateChecker(client: URLSessionClient(), current: current)
            do {
                let found = try await checker.check()
                self?.finishUpdateCheck(found)
                self?.reportUpdateCheck(found)
            } catch {
                self?.finishUpdateCheck(nil, failure: error)
                self?.reportUpdateCheck(nil, failed: true)
            }
        }
    }

    // reportUpdateCheck tells the user what a check they asked for found, and installs a newer release when
    // they choose to.
    private func reportUpdateCheck(_ found: ReleaseInfo?, failed: Bool = false) {
        let running = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        NSApp.activate()
        let alert = NSAlert()
        guard let found else {
            alert.messageText = failed ? "Couldn't reach GitHub." : "Sheepdog \(running) is the latest."
            alert.informativeText = failed
                ? "Check your connection and try again later."
                : "Tug is already on the newest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let version = found.tag.hasPrefix("v") ? String(found.tag.dropFirst()) : found.tag
        let installs = Updater.canUpdate
        alert.messageText = "Sheepdog \(version) is available."
        alert.informativeText = installs
            ? "You have \(running). Sheepdog updates itself and starts again."
            : "You have \(running). The release page has the download."
        alert.addButton(withTitle: installs ? "Update Now" : "View Release")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        guard installs else {
            NSWorkspace.shared.open(found.page)
            return
        }
        Task { [weak self] in
            do {
                try await self?.installRelease(found)
            } catch {
                self?.log.error("update install failed: \(String(describing: error), privacy: .public)")
                NSWorkspace.shared.open(found.page)
            }
        }
    }

    // installRelease installs a release through Homebrew when Homebrew manages this copy and from the
    // release's disk image otherwise.
    private func installRelease(_ release: ReleaseInfo) async throws {
        if Self.fromHomebrew {
            try await updater.brew()
        } else {
            try await updater.install(tag: release.tag)
        }
    }

    // finishUpdateCheck keeps the release a check found, or clears it when there is none.
    private func finishUpdateCheck(_ found: ReleaseInfo?, failure: Error? = nil) {
        checkingUpdate = false
        if let failure {
            log.info("update check failed: \(String(describing: failure), privacy: .public)")
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(found?.tag, forKey: Self.updateTagKey)
        defaults.set(found?.page.absoluteString, forKey: Self.updatePageKey)
    }

    // requestCalendarAccessIfNeeded asks for macOS Calendar access once, when that source is on.
    func requestCalendarAccessIfNeeded() {
        guard settings.useMacCalendar, calendar.access == .unknown, !requestingAccess else {
            return
        }
        requestingAccess = true
        Task {
            _ = await calendar.requestAccess()
            requestingAccess = false
            refresh()
        }
    }

    // refresh rereads macOS Calendar, merges the account events and drops state for meetings that are gone.
    func refresh() {
        let now = Date()
        lastRefresh = now
        requestCalendarAccessIfNeeded()
        let local = settings.useMacCalendar ? calendar.entries(now: now) : []
        meetings = EntryMerge.merge(accounts.entries + [local])
            .compactMap { Meeting(entry: $0, settings: settings) }
            .sorted { $0.start < $1.start }
        let known = Set((meetings + testMeetings).map(\.id))
        states = states.filter { known.contains($0.key) }
        tick()
    }

    // testAlarm adds a fake meeting that starts in 45 seconds, which triggers the takeover at once. During a
    // nap the test shows the alarm without sound, since a nap never makes noise.
    func testAlarm() {
        let start = Date().addingTimeInterval(45)
        let link = JoinLinkFinder.find(in: "https://meet.google.com/abc-defg-hij")
        let silent = isNapping(now: Date())
        let meeting = Meeting(
            id: "test-\(Int(start.timeIntervalSince1970))",
            title: silent ? "Test alarm (silent, Tug is napping)" : "Test alarm",
            start: start,
            end: start.addingTimeInterval(600),
            link: link
        )
        testMeetings.append(meeting)
        if silent {
            silentTests.insert(meeting.id)
        }
        tick()
    }

    // tick advances the alert state once.
    private func tick() {
        let now = Date()
        Theme.palette = settings.palette
        Theme.outfit = Theme.dressed(settings, on: now)
        accounts.refreshIfDue(now: now)
        checkForUpdateIfDue(now: now)
        if now.timeIntervalSince(lastRefresh) >= 60 {
            refresh()
            return
        }
        testMeetings.removeAll { Escalation.isExpired($0, settings: settings, now: now) || states[$0.id]?.resolution != nil }
        silentTests.formIntersection(testMeetings.map(\.id))
        if napUntil != nil && !isNapping(now: now) {
            setNap(nil)
        }
        // A nap leaves real meetings out entirely. Working hours leave out silent meetings and hold quiet ones to
        // the countdown. Test the alarm still works because it is asked for.
        let gated = isNapping(now: now)
            ? (alerting: [Meeting](), quiet: Set<String>())
            : settings.workingHours.gate(meetings, calendar: .current)
        let all = gated.alerting + testMeetings

        let chime = all.contains { meeting in
            let state = states[meeting.id] ?? MeetingState()
            return state.resolution == nil && !gated.quiet.contains(meeting.id)
                && Escalation.crossedWarning(for: meeting, settings: settings, previous: lastTick, now: now)
        }
        lastTick = now

        active = Escalation.mostUrgent(all, states: states, settings: settings, now: now, quiet: gated.quiet)
        places.places = PlaceKeeper.pruned(
            PlaceKeeper.handedBack(places.places, now: now, micInUse: mic.isRunning),
            now: now,
            calendar: .current
        )
        render(now: now, chime: chime)
        renderHandBack()
        renderUpdateCard(now: now)
        onTick?()
    }

    // render shows the right surface for the active meeting.
    private func render(now: Date, chime: Bool) {
        model.now = now
        followDraft(to: active?.meeting)
        model.askPlace = settings.holdPlace
        model.slackChannels = settings.validSlackChannels
        if model.teamChannel >= model.slackChannels.count {
            model.teamChannel = 0
        }
        if model.slackChannels.isEmpty {
            model.messagingTeam = false
        }
        model.heldNote = active.flatMap { active in places.places.first { $0.id == active.meeting.id }?.note }
        guard let active else {
            sounds.stopAlarm()
            windows.hideAll()
            model.meeting = nil
            return
        }
        let state = states[active.meeting.id] ?? MeetingState()
        model.meeting = active.meeting
        model.snoozesLeft = max(0, settings.maxSnoozes - state.snoozeCount)
        model.snoozeLength = now < active.meeting.start ? settings.snoozeBeforeStart : settings.snoozeAfterStart
        model.takeoverLead = settings.takeoverLead

        switch active.stage {
        case .takeover:
            if !windows.isShowingTakeover {
                commitDraft()
            }
            windows.showTakeover()
            if state.quieted || silentTests.contains(active.meeting.id) {
                sounds.stopAlarm()
            } else {
                sounds.startAlarm(
                    settings: settings,
                    melody: BarkMelody.current(outfit: Theme.season(on: now), settings: settings)
                )
            }
        case .warning:
            sounds.stopAlarm()
            model.editingInTakeover = false
            model.messagingTeam = false
            windows.hideTakeover()
            if Escalation.showsPill(state, settings: settings) {
                windows.showPill()
            } else {
                windows.hidePill()
            }
            if chime && !silentTests.contains(active.meeting.id) {
                sounds.chime(settings: settings)
            }
        case .idle:
            sounds.stopAlarm()
            windows.hideAll()
        }
    }

    // isNapping reports whether Tug is asleep at now.
    func isNapping(now: Date = Date()) -> Bool {
        Nap.isNapping(until: napUntil, now: now)
    }

    // nap puts Tug to sleep for the chosen length, which silences every real meeting until he wakes.
    func nap(_ length: NapLength) {
        setNap(Nap.until(length, now: Date(), calendar: .current, hours: settings.workingHours))
        tick()
    }

    // wake ends a nap. Meetings still in their alert window alert at once.
    func wake() {
        setNap(nil)
        tick()
    }

    // setNap stores the nap's end, or clears it.
    private func setNap(_ until: Date?) {
        napUntil = until
        if let until {
            UserDefaults.standard.set(until, forKey: Self.napKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.napKey)
        }
    }

    // join opens the active meeting's link and resolves it as joined.
    func join() {
        guard let meeting = active?.meeting else {
            return
        }
        open(meeting)
        resolveActive(.joined)
    }

    // open launches a meeting link in its native app, falling back to the browser.
    func open(_ meeting: Meeting) {
        guard let link = meeting.link else {
            return
        }
        windows.forgetPreviousApp()
        if !NSWorkspace.shared.open(link.native) {
            NSWorkspace.shared.open(link.web)
        }
    }

    // openInCalendar shows a meeting where it lives, falling back to Calendar.app when the event has no
    // page or its page does not open.
    func openInCalendar(_ meeting: Meeting) {
        if let page = meeting.webURL, NSWorkspace.shared.open(page) {
            return
        }
        if let calendar = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendar, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // toggleTeamRow opens or closes the takeover's Let them know row, saving any typed note
    // first so the note field and the row are never open together.
    private func toggleTeamRow() {
        if !model.messagingTeam {
            commitDraft()
        }
        model.messagingTeam.toggle()
    }

    // sendTeamMessage copies a ready-made line for the active meeting, opens the picked Slack channel
    // and gets the alarm off the screen so the user can paste. Running late keeps the countdown, and
    // can't make it skips the meeting.
    private func sendTeamMessage(_ message: TeamMessage) {
        let channels = settings.validSlackChannels
        guard let meeting = active?.meeting, !channels.isEmpty,
              let link = channels[min(model.teamChannel, channels.count - 1)].channelLink else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text(title: meeting.title), forType: .string)
        model.messagingTeam = false
        windows.forgetPreviousApp()
        openInSlack(link)
        switch message {
        case .runningLate:
            closeTakeover()
        case .cantMake:
            resolveActive(.skipped)
        }
    }

    // openInSlack opens the channel in the Slack app. A Copy link carries no team id, so there is no
    // slack:// form, but the Slack app opens the web link itself when handed it directly. The
    // browser is the fallback when Slack is not installed.
    private func openInSlack(_ link: SlackLink) {
        if link.native != link.web, NSWorkspace.shared.open(link.native) {
            return
        }
        guard let slack = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.slackBundleID) else {
            NSWorkspace.shared.open(link.web)
            return
        }
        NSWorkspace.shared.open([link.web], withApplicationAt: slack, configuration: NSWorkspace.OpenConfiguration())
    }

    // snooze applies one snooze to the active meeting.
    private func snooze() {
        guard let meeting = active?.meeting else {
            return
        }
        states[meeting.id] = Escalation.snoozed(states[meeting.id] ?? MeetingState(), meeting: meeting, settings: settings, now: Date())
        tick()
    }

    // closeTakeover drops the active meeting's takeover back to the silent pill for the rest of its
    // alert window.
    private func closeTakeover() {
        guard let meeting = active?.meeting else {
            return
        }
        commitDraft()
        states[meeting.id] = Escalation.closedTakeover(states[meeting.id] ?? MeetingState())
        tick()
    }

    // hidePill closes the countdown for the active meeting and leaves its chimes and takeover in place.
    private func hidePill() {
        guard let meeting = active?.meeting else {
            return
        }
        commitDraft()
        var state = states[meeting.id] ?? MeetingState()
        state.pillHidden = true
        states[meeting.id] = state
        tick()
    }

    // resolveActive marks the active meeting joined or skipped and silences it.
    private func resolveActive(_ resolution: Resolution) {
        guard let meeting = active?.meeting else {
            return
        }
        resolve(meeting, resolution)
    }

    // resolve marks a meeting joined or skipped.
    func resolve(_ meeting: Meeting, _ resolution: Resolution) {
        var state = states[meeting.id] ?? MeetingState()
        state.resolution = resolution
        states[meeting.id] = state
        markPlace(meeting.id, resolution)
        tick()
    }

    // micStarted resolves every meeting in its alert window as joined when a call app opens the mic.
    private func micStarted() {
        let now = Date()
        for meeting in meetings + testMeetings
        where Escalation.isInAlertWindow(meeting, settings: settings, now: now) && states[meeting.id]?.resolution == nil {
            var state = states[meeting.id] ?? MeetingState()
            state.resolution = .joined
            states[meeting.id] = state
            markPlace(meeting.id, .joined)
        }
        tick()
    }

    // state returns what the user has done about a meeting.
    func state(for meeting: Meeting) -> MeetingState {
        states[meeting.id] ?? MeetingState()
    }

    // heldPlaces lists every held or handed back note, oldest first.
    var heldPlaces: [HeldPlace] {
        places.places.sorted { $0.savedAt < $1.savedAt }
    }

    // handBackNow brings a note back at once, ahead of any others waiting.
    func handBackNow(_ id: String) {
        guard let index = places.places.firstIndex(where: { $0.id == id }) else {
            return
        }
        if places.places[index].handedBackAt == nil {
            places.places[index].handedBackAt = Date()
        }
        focusPlaceID = id
        tick()
    }

    // followDraft saves the note typed for the previous meeting when the alert moves to another one.
    private func followDraft(to meeting: Meeting?) {
        guard meeting?.id != draftMeeting?.id else {
            return
        }
        commitDraft()
        draftMeeting = meeting
        model.messagingTeam = false
    }

    // commitDraft saves the typed note, if any, for the meeting it was typed for and clears the field.
    private func commitDraft() {
        let note = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        model.draft = ""
        model.editingInTakeover = false
        guard let meeting = draftMeeting, !note.isEmpty else {
            return
        }
        places.places.removeAll { $0.id == meeting.id }
        places.places.append(HeldPlace(
            id: meeting.id,
            title: meeting.title,
            note: note,
            savedAt: Date(),
            meetingEnd: meeting.end,
            resolution: states[meeting.id]?.resolution
        ))
    }

    // holdPlace opens the takeover's note field and stops the alarm sound so the user can think.
    private func holdPlace() {
        guard let meeting = active?.meeting else {
            return
        }
        model.editingInTakeover = true
        states[meeting.id] = Escalation.quieted(states[meeting.id] ?? MeetingState())
        sounds.stopAlarm()
    }

    // saveNote holds the typed note and gives typing back to the app the user was in. A note typed
    // in the takeover also closes the takeover back to the pill.
    private func saveNote() {
        let typed = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if windows.isShowingTakeover, typed, let meeting = active?.meeting {
            states[meeting.id] = Escalation.closedTakeover(states[meeting.id] ?? MeetingState())
        }
        commitDraft()
        windows.returnKeyFromPill()
        tick()
    }

    // cancelNote empties the note field and gives typing back.
    private func cancelNote() {
        model.draft = ""
        model.editingInTakeover = false
        windows.returnKeyFromPill()
    }

    // markPlace records how a meeting with a held note was resolved.
    private func markPlace(_ id: String, _ resolution: Resolution) {
        guard let index = places.places.firstIndex(where: { $0.id == id }) else {
            return
        }
        places.places[index].resolution = resolution
    }

    // renderHandBack shows the newest handed back note, or the one picked from the menu, unless the
    // takeover is up.
    private func renderHandBack() {
        var queue = PlaceKeeper.queue(places.places)
        if let id = focusPlaceID, let index = queue.firstIndex(where: { $0.id == id }) {
            queue.insert(queue.remove(at: index), at: 0)
        } else {
            focusPlaceID = nil
        }
        model.handBack = queue.first
        model.handBackCount = queue.count
        if queue.isEmpty || windows.isShowingTakeover {
            windows.hideHandBack()
        } else {
            windows.showHandBack()
        }
    }

    // copyHandBack puts the shown note on the clipboard and leaves the card up.
    private func copyHandBack() {
        guard let note = model.handBack?.note else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note, forType: .string)
    }

    // doneHandBack drops the shown note and moves to the next one.
    private func doneHandBack() {
        guard let id = model.handBack?.id else {
            return
        }
        places.places.removeAll { $0.id == id }
        focusPlaceID = nil
        tick()
    }

    // clearHandBacks drops every handed back note, leaving notes still held for their meetings.
    private func clearHandBacks() {
        places.places = PlaceKeeper.cleared(places.places)
        focusPlaceID = nil
        tick()
    }

    // renderUpdateCard shows the update card when it is due, and keeps an open card hidden while a
    // countdown, the takeover, a call, off hours or the hand-back card is in the way.
    private func renderUpdateCard(now: Date) {
        guard let update = availableUpdate else {
            updateCardOpen = false
            model.updateVersion = nil
            windows.hideUpdate()
            return
        }
        let before = nudge
        nudge.see(update.tag, now: now)
        let alerting = active.map { $0.stage != .idle } ?? false
        let blocked = alerting || windows.isShowingTakeover || mic.isRunning || model.handBack != nil
            || settings.workingHours.isOffDuty(now: now, calendar: .current)
        if !updateCardOpen && nudge.due(now: now, blocked: blocked) {
            nudge.shown(now: now)
            updateCardOpen = true
        }
        if nudge != before {
            saveNudge()
        }
        let version = update.tag.hasPrefix("v") ? String(update.tag.dropFirst()) : update.tag
        model.updateVersion = updateCardOpen ? version : nil
        if updateCardOpen && !blocked {
            windows.showUpdate()
        } else {
            windows.hideUpdate()
        }
    }

    // openUpdate installs the update when this copy can, through Homebrew when Homebrew manages it and
    // from the release's disk image otherwise. It opens the release page instead when this copy cannot
    // install, or after an install failed.
    private func openUpdate() {
        guard let update = availableUpdate else {
            closeUpdateCard()
            return
        }
        guard Updater.canUpdate, !model.updateFailed else {
            NSWorkspace.shared.open(update.page)
            closeUpdateCard()
            return
        }
        model.updateBusy = true
        Task { [weak self] in
            do {
                try await self?.installRelease(update)
            } catch {
                self?.log.error("update install failed: \(String(describing: error), privacy: .public)")
                self?.model.updateFailed = true
            }
            self?.model.updateBusy = false
        }
    }

    // skipUpdate stops the card for this version. The next version starts fresh.
    private func skipUpdate() {
        nudge.skip()
        saveNudge()
        closeUpdateCard()
    }

    // closeUpdateCard puts the card away until its next reminder is due.
    private func closeUpdateCard() {
        updateCardOpen = false
        model.updateVersion = nil
        windows.hideUpdate()
    }

    // saveNudge keeps the update card's schedule across restarts.
    private func saveNudge() {
        if let data = try? JSONEncoder().encode(nudge) {
            UserDefaults.standard.set(data, forKey: Self.nudgeKey)
        }
    }
}
