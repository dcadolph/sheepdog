import AppKit
import SwiftUI

// AppDelegate starts Sheepdog and owns its long-lived objects.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // settingsStore holds the live settings.
    private let settingsStore = SettingsStore()
    // loginItem starts Sheepdog at login.
    private let loginItem = LoginItem()
    // accounts holds the Microsoft and Google sign-ins.
    private let accounts = Accounts()
    // coordinator runs the alert loop.
    private var coordinator: Coordinator?
    // statusItem is the menu bar controller.
    private var statusItem: StatusItemController?
    // settingsWindow is created on first open and reused.
    private var settingsWindow: NSWindow?

    // applicationDidFinishLaunching builds the menu bar item and starts the loop.
    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItem.configureOnFirstLaunch()
        let coordinator = Coordinator(settingsStore: settingsStore, accounts: accounts)
        let statusItem = StatusItemController(coordinator: coordinator) { [weak self] in
            self?.showSettings()
        }
        coordinator.onTick = { [weak statusItem] in statusItem?.update() }
        self.coordinator = coordinator
        self.statusItem = statusItem
        coordinator.start()
    }

    // showSettings opens the settings window and brings it forward.
    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                store: settingsStore,
                loginItem: loginItem,
                accounts: accounts,
                onSourcesChanged: { [weak self] in self?.coordinator?.refresh() },
                onTestAlarm: { [weak self] in self?.coordinator?.testAlarm() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Sheepdog Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
if let flag = CommandLine.arguments.firstIndex(of: DemoRenderer.argument) {
    let dir = CommandLine.arguments.dropFirst(flag + 1).first ?? "demo-frames"
    exit(MainActor.assumeIsolated { DemoRenderer.run(dir: dir) })
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
