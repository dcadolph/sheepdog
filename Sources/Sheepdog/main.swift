import AppKit
import SwiftUI

// AppDelegate starts Sheepdog and owns its long-lived objects.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // settingsStore holds the live settings.
    private let settingsStore = SettingsStore()
    // loginItem starts Sheepdog at login.
    private let loginItem = LoginItem()
    // coordinator runs the alert loop.
    private var coordinator: Coordinator?
    // statusItem is the menu bar controller.
    private var statusItem: StatusItemController?
    // settingsWindow is created on first open and reused.
    private var settingsWindow: NSWindow?

    // applicationDidFinishLaunching builds the menu bar item and starts the loop.
    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItem.configureOnFirstLaunch()
        let coordinator = Coordinator(settingsStore: settingsStore)
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
            let view = SettingsView(store: settingsStore, loginItem: loginItem) { [weak self] in
                self?.coordinator?.testAlarm()
            }
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
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
