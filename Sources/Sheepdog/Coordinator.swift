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
        model.onCloseTakeover = { [weak self] in self?.closeTakeover() }
        model.onClosePill = { [weak self] in self?.hidePill() }
        model.onSaveNote = { [weak self] in self?.saveNote() }
        model.onHoldPlace = { [weak self] in self?.holdPlace() }
        model.onCancelNote = { [weak self] in self?.cancelNote() }
        model.onCopyHandBack = { [weak self] in self?.copyHandBack() }
        model.onDoneHandBack = { [weak self] in self?.doneHandBack() }
        model.onClearHandBacks = { [weak self] in self?.clearHandBacks() }
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
        places.places = PlaceKeeper.pruned(
            PlaceKeeper.handedBack(places.places, now: now, micInUse: mic.isRunning),
            now: now,
            calendar: .current
        )
        render(now: now, chime: chime)
        renderHandBack()
        onTick?()
    }

    // render shows the right surface for the active meeting.
    private func render(now: Date, chime: Bool) {
        model.now = now
        followDraft(to: active?.meeting)
        model.askPlace = settings.holdPlace
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
            if state.quieted {
                sounds.stopAlarm()
            } else {
                sounds.startAlarm(settings: settings)
            }
        case .warning:
            sounds.stopAlarm()
            model.editingInTakeover = false
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
}
