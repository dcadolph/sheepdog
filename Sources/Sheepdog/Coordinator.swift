import AppKit
import Foundation

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
    // meetings are the upcoming meetings from the calendar.
    private(set) var meetings: [Meeting] = []
    // testMeetings are fake meetings created by Test the alarm.
    private var testMeetings: [Meeting] = []
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
        model.onClosePill = { [weak self] in self?.hidePill() }
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

    // testAlarm adds a fake meeting that starts in 45 seconds, which triggers the takeover at once.
    func testAlarm() {
        let start = Date().addingTimeInterval(45)
        let link = JoinLinkFinder.find(in: "https://meet.google.com/abc-defg-hij")
        let meeting = Meeting(
            id: "test-\(Int(start.timeIntervalSince1970))",
            title: "Test alarm",
            start: start,
            end: start.addingTimeInterval(600),
            link: link
        )
        testMeetings.append(meeting)
        tick()
    }

    // tick advances the alert state once.
    private func tick() {
        let now = Date()
        accounts.refreshIfDue(now: now)
        if now.timeIntervalSince(lastRefresh) >= 60 {
            refresh()
            return
        }
        testMeetings.removeAll { Escalation.isExpired($0, settings: settings, now: now) || states[$0.id]?.resolution != nil }
        let all = meetings + testMeetings

        let chime = all.contains { meeting in
            let state = states[meeting.id] ?? MeetingState()
            return state.resolution == nil
                && Escalation.crossedWarning(for: meeting, settings: settings, previous: lastTick, now: now)
        }
        lastTick = now

        active = Escalation.mostUrgent(all, states: states, settings: settings, now: now)
        render(now: now, chime: chime)
        onTick?()
    }

    // render shows the right surface for the active meeting.
    private func render(now: Date, chime: Bool) {
        model.now = now
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

        switch active.stage {
        case .takeover:
            windows.showTakeover()
            sounds.startAlarm(settings: settings)
        case .warning:
            sounds.stopAlarm()
            windows.hideTakeover()
            if Escalation.showsPill(state, settings: settings) {
                windows.showPill()
            } else {
                windows.hidePill()
            }
            if chime {
                sounds.chime(settings: settings)
            }
        case .idle:
            sounds.stopAlarm()
            windows.hideAll()
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

    // snooze applies one snooze to the active meeting.
    private func snooze() {
        guard let meeting = active?.meeting else {
            return
        }
        states[meeting.id] = Escalation.snoozed(states[meeting.id] ?? MeetingState(), meeting: meeting, settings: settings, now: Date())
        tick()
    }

    // hidePill closes the countdown for the active meeting and leaves its chimes and takeover in place.
    private func hidePill() {
        guard let meeting = active?.meeting else {
            return
        }
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
        }
        tick()
    }

    // state returns what the user has done about a meeting.
    func state(for meeting: Meeting) -> MeetingState {
        states[meeting.id] ?? MeetingState()
    }
}
