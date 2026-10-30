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
    // log records each update step under the com.dcadolph.sheepdog subsystem.
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
    // stagedKey is the user defaults key holding the tag of a verified update waiting for a quiet moment.
    private static let stagedKey = "updateStaged"
    // attemptKey is the user defaults key holding the tag just swapped in, read on the next launch.
    private static let attemptKey = "updateAttempt"
    // failedKey is the user defaults key holding the tags that were swapped in and never started.
    private static let failedKey = "updateFailed"
    // toldKey is the user defaults key recording that the user was told updates install on their own.
    private static let toldKey = "autoUpdateTold"
    // lastRunKey is the user defaults key holding the version of the last launch.
    private static let lastRunKey = "lastRunVersion"
    // oldNudgeKey is the user defaults key the update card's schedule was kept under before 1.17.0.
    private static let oldNudgeKey = "updateNudge"
    // releasesPage is Sheepdog's releases page on GitHub.
    private static let releasesPage = URL(string: "https://github.com/dcadolph/sheepdog/releases")!
    // noticeOpen reports that the notice card holds a notice not yet answered. A blocked card hides and
    // comes back when the way is clear.
    private var noticeOpen: Bool { model.notice != nil }
    // setupNudgeKey is the user defaults key holding the setup card's schedule.
    private static let setupNudgeKey = "setupNudge"
    // setupNudge is when the setup card last showed and whether it was silenced. It is not part of the
    // settings backup.
    private var setupNudge: SetupNudge = UserDefaults.standard.data(forKey: Coordinator.setupNudgeKey)
        .flatMap { try? JSONDecoder().decode(SetupNudge.self, from: $0) } ?? SetupNudge()
    // setupHints are the calendar setup hints from the last refresh.
    private var setupHints: [SetupHint] = []
    // setupCardOpen reports that the setup card was shown and not yet answered. A blocked card hides
    // and comes back when the way is clear.
    private var setupCardOpen = false
    // onShowCalendars opens Settings on the Calendars tab.
    var onShowCalendars: (() -> Void)?
    // setupFlowOpen reports that the setup window is pending or showing. It holds the macOS Calendar
    // prompt until the user asks for it and keeps the cards off the window.
    var setupFlowOpen = false
    // onShowSettings opens Settings on the General tab.
    var onShowSettings: (() -> Void)?
    // support is Sheepdog's Application Support folder, which holds the launch marker and the bundle
    // an update replaced.
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.dcadolph.sheepdog", isDirectory: true)
    // marker records each launch, so the relaunch helper can roll back a build that never starts.
    static let marker = LaunchMarker(folder: support)
    // updateCache is where downloads are staged.
    private static let updateCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.dcadolph.sheepdog", isDirectory: true)
        .appendingPathComponent("updates", isDirectory: true)
    // build is this build's CFBundleVersion, which the launch marker records.
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    // updater checks for, verifies and installs newer releases.
    private(set) lazy var updater = makeUpdater()
    // runningVersion is this build's version, or nil outside the app bundle.
    private static let runningVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String).flatMap(ReleaseVersion.init)
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
    // firstRunKey is the user defaults key holding when this Mac first ran Sheepdog. It is not part of
    // the settings backup.
    private static let firstRunKey = "setupFirstRun"
    // lastMeetingKey is the user defaults key holding when Tug last saw a real meeting. It is not part
    // of the settings backup.
    private static let lastMeetingKey = "setupLastMeetingSeen"

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
        model.onNoticeAction = { [weak self] in self?.answerNotice(act: true) }
        model.onDismissNotice = { [weak self] in self?.answerNotice(act: false) }
        model.onOpenSetup = { [weak self] in self?.openSetup() }
        model.onLaterSetup = { [weak self] in self?.answerSetup(silence: false) }
        model.onSilenceSetup = { [weak self] in self?.answerSetup(silence: true) }
        UserDefaults.standard.removeObject(forKey: Self.oldNudgeKey)
        calendar.onChange = { [weak self] in self?.refresh() }
        accounts.onChange = { [weak self] in self?.refresh() }
        mic.onStart = { [weak self] in self?.micStarted() }
    }

    // start asks for calendar access when macOS Calendar is in use, reads the accounts and begins ticking.
    func start() {
        if UserDefaults.standard.object(forKey: Self.firstRunKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.firstRunKey)
        }
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

    // checkForUpdateIfDue asks GitHub for the latest release when a check is due, and with installs on
    // fetches, verifies and stages it. The time is recorded before the request, so a failure waits for
    // the next check instead of retrying every tick.
    private func checkForUpdateIfDue(now: Date) {
        let defaults = UserDefaults.standard
        guard settings.checkForUpdates, !checkingUpdate, !updater.state.busy, Self.runningVersion != nil,
            UpdateSchedule.isDue(
                lastChecked: defaults.object(forKey: Self.updateCheckedKey) as? Date, launched: launched, now: now
            )
        else {
            return
        }
        defaults.set(now, forKey: Self.updateCheckedKey)
        checkingUpdate = true
        let install = settings.checkForUpdates && settings.installUpdates
        Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await self.updater.check(automatic: true, install: install)
                self.finishUpdateCheck(found)
            } catch {
                self.finishUpdateCheck(nil, failure: error)
            }
        }
    }

    // checkForUpdateNow asks GitHub for the latest release at once, whatever the schedule or the automatic
    // check setting says, and answers in a dialog.
    func checkForUpdateNow() {
        guard !checkingUpdate, Self.runningVersion != nil else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: Self.updateCheckedKey)
        checkingUpdate = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await self.updater.check(
                    automatic: self.settings.checkForUpdates, install: false, forced: true)
                self.finishUpdateCheck(found)
                self.reportUpdateCheck(found)
            } catch {
                self.finishUpdateCheck(nil, failure: error)
                self.reportUpdateCheck(nil, failed: true)
            }
        }
    }

    // reportUpdateCheck tells the user what a check they asked for found. Update Now downloads, verifies
    // and installs the release at once, without waiting for a quiet moment, and opens the release page
    // when it is refused.
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
        let installs = Updater.replaceable(updater.bundle)
        alert.messageText = "Sheepdog \(version) is available."
        alert.informativeText = installs
            ? "You have \(running). Sheepdog checks the download's Apple signature, updates itself and starts again."
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
            guard let self else { return }
            await self.updater.fetch(found)
            if case .verified = self.updater.state {
                self.updater.installNow()
            } else {
                NSWorkspace.shared.open(found.page)
            }
        }
    }

    // finishUpdateCheck keeps the release a check found, or clears it when there is none.
    private func finishUpdateCheck(_ found: ReleaseInfo?, failure: Error? = nil) {
        checkingUpdate = false
        if let failure {
            log.info("update: check failed: \(String(describing: failure), privacy: .public)")
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(found?.tag, forKey: Self.updateTagKey)
        defaults.set(found?.page.absoluteString, forKey: Self.updatePageKey)
    }

    // makeUpdater builds the updater for the running bundle, skipping tags that failed to start.
    private func makeUpdater() -> Updater {
        let current = Self.runningVersion ?? ReleaseVersion("0.0.0")!
        let failed = UserDefaults.standard.stringArray(forKey: Self.failedKey) ?? []
        let updater = Updater(
            client: URLSessionClient(), downloader: URLSessionDownloader(),
            trust: CodeTrustCheck(current: current, running: CodeTrust.runningRequirement()), current: current,
            bundle: Installer.originalURL(Bundle.main.bundleURL), cache: Self.updateCache, skip: Set(failed))
        updater.log = { [log] line in log.notice("update: \(line, privacy: .public)") }
        updater.changed = { [weak self] in
            guard let self else { return }
            if case .verified(let tag) = self.updater.state {
                UserDefaults.standard.set(tag, forKey: Self.stagedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.stagedKey)
            }
            self.onTick?()
        }
        updater.quiet = { [weak self] in self?.quietMoment(now: Date()) ?? false }
        updater.install = { [weak self] staged, tag in self?.installUpdate(staged, tag: tag) }
        return updater
    }

    // quietMoment reports whether a relaunch would interrupt nothing: no alarm, card, call or open
    // Sheepdog window, on duty, no meeting within 15 minutes or under way, and no input for 30 seconds.
    private func quietMoment(now: Date) -> Bool {
        let anyInput = CGEventType(rawValue: ~0)!
        let alerting = active.map { $0.stage != .idle } ?? false
        let busy = alerting || windows.isShowingTakeover || model.handBack != nil || setupCardOpen
            || setupFlowOpen || mic.isRunning
            || NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        return UpdateGate.quiet(
            idleSeconds: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput),
            busy: busy, offDuty: settings.workingHours.isOffDuty(now: now, calendar: .current),
            meetings: (meetings + testMeetings).map { (start: $0.start, end: $0.end) }, now: now)
    }

    // installUpdate swaps the staged bundle in, starts the helper that relaunches it and rolls back a
    // build that never starts, and quits.
    private func installUpdate(_ staged: URL, tag: String) {
        let bundle = updater.bundle
        let previous = Self.support.appendingPathComponent("previous", isDirectory: true)
            .appendingPathComponent(Updater.appName)
        let build =
            (NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))?["CFBundleVersion"]
                as? String) ?? ""
        let backup: URL
        do {
            backup = try Updater.swap(bundle: bundle, staged: staged, previous: previous)
        } catch {
            log.error("update: swap failed: \(error.localizedDescription, privacy: .public)")
            updater.refuse(.location, tag)
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(tag, forKey: Self.attemptKey)
        defaults.removeObject(forKey: Self.stagedKey)
        var plan = Relaunch.Plan(bundle: bundle)
        plan.previous = backup
        plan.failed = Self.support.appendingPathComponent("failed-\(tag).app")
        plan.marker = Self.marker.marker
        plan.build = build
        do {
            try Relaunch.start(plan)
        } catch {
            log.error("update: relaunch failed: \(error.localizedDescription, privacy: .public)")
        }
        log.notice("update: relaunch into \(tag, privacy: .public) build \(build, privacy: .public)")
        NSApp.terminate(nil)
    }

    // installStaged installs a verified update that found no quiet moment before the last Quit,
    // verifying it again first, and reports whether Sheepdog is quitting to relaunch it.
    func installStaged() -> Bool {
        let defaults = UserDefaults.standard
        guard let tag = defaults.string(forKey: Self.stagedKey) else { return false }
        defaults.removeObject(forKey: Self.stagedKey)
        let staged = Self.updateCache.appendingPathComponent(tag, isDirectory: true)
            .appendingPathComponent("unpacked", isDirectory: true).appendingPathComponent(Updater.appName)
        guard settings.checkForUpdates, settings.installUpdates, let version = ReleaseVersion(tag),
            let current = Self.runningVersion, version > current, Updater.replaceable(updater.bundle),
            FileManager.default.fileExists(atPath: staged.path)
        else { return false }
        let name = String(tag.dropFirst(tag.hasPrefix("v") ? 1 : 0))
        if let step = updater.trust.verify(bundle: staged, version: name) {
            log.notice("update: staged \(tag, privacy: .public) refused at \(step.rawValue, privacy: .public)")
            return false
        }
        log.notice("update: installing \(tag, privacy: .public) staged before the last quit")
        installUpdate(staged, tag: tag)
        return true
    }

    // settleAttempt reads how the last install went. A tag this build is not at never started, so it is
    // never fetched again, and the notice card says so.
    func settleAttempt() {
        let defaults = UserDefaults.standard
        guard let tag = defaults.string(forKey: Self.attemptKey) else { return }
        defaults.removeObject(forKey: Self.attemptKey)
        guard ReleaseVersion(tag) != Self.runningVersion else { return }
        var failed = defaults.stringArray(forKey: Self.failedKey) ?? []
        failed.append(tag)
        defaults.set(failed, forKey: Self.failedKey)
        let running = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let name = String(tag.dropFirst(tag.hasPrefix("v") ? 1 : 0))
        log.error("update: \(tag, privacy: .public) did not start, back on \(running, privacy: .public)")
        model.notice = Notice(
            title: "Sheepdog \(name) did not start",
            body: "Tug went back to \(running) and will not try \(name) again.",
            button: "Open Release Page", action: .page(Self.releasesPage.appendingPathComponent("tag/\(tag)")))
    }

    // releaseMessage says once that Sheepdog was updated, on the first launch of a new version. The
    // first automatic update also says updates now install on their own.
    func releaseMessage() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: Self.lastRunKey)
        defaults.set(version, forKey: Self.lastRunKey)
        guard let last, last != version, !version.isEmpty, model.notice == nil else { return }
        if !defaults.bool(forKey: Self.toldKey), settings.checkForUpdates, settings.installUpdates {
            defaults.set(true, forKey: Self.toldKey)
            model.notice = Notice(
                title: "Sheepdog updated to \(version)",
                body: "Sheepdog now installs updates on its own. Change that in Settings.",
                button: "Open Settings", action: .settings)
            return
        }
        model.notice = Notice(
            title: "Sheepdog updated to \(version)", body: "Updated from \(last).", button: "What's New",
            action: .page(Self.releasesPage.appendingPathComponent("tag/v\(version)")))
    }

    // requestCalendarAccessIfNeeded asks for macOS Calendar access once, when that source is on.
    func requestCalendarAccessIfNeeded() {
        guard settings.useMacCalendar, calendar.access == .unknown, !requestingAccess, !setupFlowOpen else {
            return
        }
        requestingAccess = true
        Task {
            _ = await calendar.requestAccess()
            requestingAccess = false
            refresh()
        }
    }

    // requestCalendarAccess asks for macOS Calendar access from the setup window and reports whether it
    // was granted. It asks only once; later calls report the answer already given.
    func requestCalendarAccess() async -> Bool {
        if calendar.access == .unknown && !requestingAccess {
            requestingAccess = true
            _ = await calendar.requestAccess()
            requestingAccess = false
            refresh()
        }
        return calendar.access == .granted
    }

    // calendarAccessGranted reports whether macOS Calendar access is granted.
    var calendarAccessGranted: Bool {
        calendar.access == .granted
    }

    // isAlerting reports that a countdown, the takeover or the hand-back card is up, so the setup window waits.
    var isAlerting: Bool {
        (active.map { $0.stage != .idle } ?? false) || windows.isShowingTakeover || model.handBack != nil
    }

    // finishSetupFlow records that the setup window closed, counts the setup card as shown so it does not
    // follow straight after, and asks for macOS Calendar access if the window never did.
    func finishSetupFlow() {
        setupFlowOpen = false
        setupNudge.shown(now: Date())
        saveSetupNudge()
        refresh()
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
        noteMeetingSeen(now: now)
        checkSetup(now: now)
        tick()
    }

    // checkSetup rereads the calendar setup hints. It waits for the macOS Calendar answer, so the card
    // never shows before the permission prompt is settled.
    private func checkSetup(now: Date) {
        guard !requestingAccess, !(settings.useMacCalendar && calendar.access == .unknown) else {
            return
        }
        setupHints = CalendarSetup.hints(setupFacts(now: now))
        let before = setupNudge
        setupNudge.see(hints: setupHints)
        if setupNudge != before {
            saveSetupNudge()
        }
    }

    // noteMeetingSeen records that Tug sees a real meeting, at most once an hour, for the quiet week
    // hint.
    private func noteMeetingSeen(now: Date) {
        guard !meetings.isEmpty else {
            return
        }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.lastMeetingKey) as? Date
        if last.map({ now.timeIntervalSince($0) >= 3600 || now < $0 }) ?? true {
            defaults.set(now, forKey: Self.lastMeetingKey)
        }
    }

    // setupFacts gathers what the calendar setup hints look at. Installed apps are found by bundle id
    // through Launch Services, which reads nothing from those apps and asks for no permission.
    func setupFacts(now: Date = Date()) -> SetupFacts {
        let access: SetupAccess
        switch calendar.access {
        case .granted:
            access = .granted
        case .denied:
            access = .denied
        case .unknown:
            access = .unknown
        }
        var available: Set<AccountKind> = []
        var connected: Set<AccountKind> = []
        for kind in AccountKind.allCases {
            switch accounts.states[kind] ?? .notConfigured {
            case .notConfigured:
                continue
            case .connected, .needsSignIn:
                connected.insert(kind)
            case .signedOut, .signingIn:
                break
            }
            available.insert(kind)
        }
        let defaults = UserDefaults.standard
        return SetupFacts(
            macCalendarOn: settings.useMacCalendar,
            macCalendarAccess: access,
            sources: settings.useMacCalendar ? calendar.sources() : [],
            availableKinds: available,
            connectedKinds: connected,
            installedApps: CalendarSetup.microsoftApps.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            },
            lastMeetingSeen: defaults.object(forKey: Self.lastMeetingKey) as? Date,
            firstRun: defaults.object(forKey: Self.firstRunKey) as? Date,
            now: now
        )
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
        renderNotice(now: now)
        renderSetupCard(now: now)
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

    // open launches a meeting link in the app or the browser, as chosen for its provider in settings.
    func open(_ meeting: Meeting) {
        guard let link = meeting.link else {
            return
        }
        windows.forgetPreviousApp()
        switch link.route(settings.joinOpens.choice(for: link.provider)) {
        case let .open(url, fallback):
            if !NSWorkspace.shared.open(url), let fallback {
                NSWorkspace.shared.open(fallback)
            }
        case let .handTo(bundleID, url, fallback):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                NSWorkspace.shared.open(fallback)
                return
            }
            NSWorkspace.shared.open(
                [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
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
        let slack = NSWorkspace.shared.urlForApplication(withBundleIdentifier: JoinLink.slackBundleID)
        guard let slack else {
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

    // renderNotice shows the notice card, and keeps it hidden while a countdown, the takeover, a call,
    // off hours, the hand-back card or the setup card is in the way.
    private func renderNotice(now: Date) {
        guard noticeOpen else {
            windows.hideNotice()
            return
        }
        let alerting = active.map { $0.stage != .idle } ?? false
        let blocked = alerting || windows.isShowingTakeover || mic.isRunning || model.handBack != nil
            || setupCardOpen || setupFlowOpen || settings.workingHours.isOffDuty(now: now, calendar: .current)
        if blocked {
            windows.hideNotice()
        } else {
            windows.showNotice()
        }
    }

    // answerNotice puts the notice card away, and with act set does what its button names first.
    private func answerNotice(act: Bool) {
        if act, let notice = model.notice {
            switch notice.action {
            case .settings:
                onShowSettings?()
            case .page(let url):
                NSWorkspace.shared.open(url)
            }
        }
        model.notice = nil
        windows.hideNotice()
    }

    // renderSetupCard shows the setup card when it is due, and keeps an open card hidden while a
    // countdown, the takeover, a call, a nap, off hours, the hand-back card or the notice card is in
    // the way.
    private func renderSetupCard(now: Date) {
        guard !setupHints.isEmpty else {
            closeSetupCard()
            return
        }
        let alerting = active.map { $0.stage != .idle } ?? false
        let blocked = alerting || windows.isShowingTakeover || mic.isRunning || model.handBack != nil
            || noticeOpen || setupFlowOpen || isNapping(now: now)
            || settings.workingHours.isOffDuty(now: now, calendar: .current)
        if !setupCardOpen && setupNudge.due(now: now, blocked: blocked) {
            setupCardOpen = true
        }
        model.setupHints = setupCardOpen ? setupHints : []
        if setupCardOpen && !blocked {
            windows.showSetup()
        } else {
            windows.hideSetup()
        }
    }

    // openSetup opens Settings on the Calendars tab and counts the card as shown.
    private func openSetup() {
        answerSetup(silence: false)
        onShowCalendars?()
    }

    // answerSetup puts the setup card away, until its next reminder or, when silence is set, for good.
    private func answerSetup(silence: Bool) {
        if silence {
            setupNudge.silence()
        } else {
            setupNudge.shown(now: Date())
        }
        saveSetupNudge()
        closeSetupCard()
    }

    // closeSetupCard hides the setup card.
    private func closeSetupCard() {
        setupCardOpen = false
        model.setupHints = []
        windows.hideSetup()
    }

    // saveSetupNudge keeps the setup card's schedule across restarts.
    private func saveSetupNudge() {
        if let data = try? JSONEncoder().encode(setupNudge) {
            UserDefaults.standard.set(data, forKey: Self.setupNudgeKey)
        }
    }
}
