import AppKit
import SwiftUI

import SheepdogCore

// SetupWindow owns the "Set up Sheepdog" window, decides when it opens and records when it is finished.
@MainActor
final class SetupWindow: NSObject, NSWindowDelegate {
    // recordKey is the user defaults key holding the setup record. It is not part of the settings backup.
    private static let recordKey = "setupFlow"
    // settingsKey is the user defaults key SettingsStore writes on its first save.
    private static let settingsKey = "alertSettings"

    // store holds the live settings.
    private let store: SettingsStore
    // accounts holds the calendar sign-ins.
    private let accounts: Accounts
    // loginItem starts Sheepdog at login.
    private let loginItem: LoginItem
    // coordinator runs the alert loop.
    private let coordinator: Coordinator
    // onAllowAccess opens Calendar privacy settings.
    private let onAllowAccess: () -> Void
    // window is the open setup window, or nil when closed.
    private var window: NSWindow?
    // pending holds the steps waiting to show at launch, until no alarm is up.
    private var pending: [SetupStep] = []
    // fresh reports that this launch is the first on this Mac.
    private let fresh: Bool

    // init reads whether this is a fresh install before anything saves settings.
    init(store: SettingsStore, accounts: Accounts, loginItem: LoginItem, coordinator: Coordinator,
         onAllowAccess: @escaping () -> Void) {
        self.store = store
        self.accounts = accounts
        self.loginItem = loginItem
        self.coordinator = coordinator
        self.onAllowAccess = onAllowAccess
        fresh = UserDefaults.standard.data(forKey: Self.settingsKey) == nil && !LoginItem.hasConfigured
        super.init()
    }

    // prepare works out the launch's steps and holds the calendar prompt while they wait. It reports whether
    // the window will open, so the caller can leave the login item for the Done step.
    func prepare() -> Bool {
        let record = UserDefaults.standard.data(forKey: Self.recordKey)
            .flatMap { try? JSONDecoder().decode(SetupFlowRecord.self, from: $0) }
        if SetupFlow.resetsHolidays(fresh: fresh, record: record) {
            store.settings.showOutfits = false
            store.settings.holidayTunes = false
        }
        pending = SetupFlow.steps(fresh: fresh, record: record)
        coordinator.setupFlowOpen = !pending.isEmpty
        return !pending.isEmpty
    }

    // showIfPending opens the launch's window once no countdown, takeover or hand-back card is up.
    func showIfPending() {
        guard !pending.isEmpty, window == nil, !coordinator.isAlerting else {
            return
        }
        let steps = pending
        pending = []
        open(steps: steps, upgrade: !fresh)
    }

    // reopen opens the window from Tug's menu at the connect step, or at access when it is still needed.
    func reopen() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let steps = SetupFlow.reopenSteps(
            accessGranted: coordinator.calendarAccessGranted,
            usesMacCalendar: store.settings.useMacCalendar
        )
        coordinator.setupFlowOpen = true
        open(steps: steps, upgrade: false)
    }

    // open builds and shows the window for the steps.
    private func open(steps: [SetupStep], upgrade: Bool) {
        loginItem.refresh()
        let state = SetupFlowState(
            steps: steps,
            upgrade: upgrade,
            startAtLogin: SetupFlow.startsAtLogin(
                fresh: fresh,
                configured: LoginItem.hasConfigured,
                enabled: loginItem.isEnabled,
                needsApproval: loginItem.needsApproval
            )
        )
        let view = SetupFlowView(
            state: state,
            store: store,
            accounts: accounts,
            setupFacts: { [weak self] in self?.coordinator.setupFacts() ?? SetupFacts(now: Date()) },
            onSourcesChanged: { [weak self] in self?.coordinator.refresh() },
            onAllowAccess: onAllowAccess,
            onRequestAccess: { [weak self] in await self?.coordinator.requestCalendarAccess() ?? false },
            onTestAlarm: { [weak self] in self?.coordinator.testAlarm() },
            onDone: { [weak self] login in
                guard let self else {
                    return false
                }
                loginItem.finishSetup(enabled: login)
                return login && loginItem.needsApproval
            },
            onClose: { [weak self] in self?.window?.close() },
            onOpenLoginItems: { [weak self] in self?.loginItem.openSystemSettings() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Set up Sheepdog"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // windowWillClose counts the flow as finished however it closed, so it shows only once.
    func windowWillClose(_ notification: Notification) {
        window = nil
        if !LoginItem.hasConfigured {
            loginItem.configureOnFirstLaunch()
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let record = SetupFlowRecord(completed: Date(), version: version)
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.recordKey)
        }
        coordinator.finishSetupFlow()
    }
}
