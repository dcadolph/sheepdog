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
    // installer puts a downloaded copy into Applications and tidies the disk image after.
    private let installer = Installer()
    // coordinator runs the alert loop.
    private var coordinator: Coordinator?
    // statusItem is the menu bar controller.
    private var statusItem: StatusItemController?
    // settingsWindow is created on first open and reused.
    private var settingsWindow: NSWindow?

    // applicationDidFinishLaunching builds the menu bar item and starts the loop. The install offer comes
    // before the hand-off so a newer copy opened from a disk image replaces a running one instead of
    // deferring to it, and before the login item so a disk image path is never registered.
    func applicationDidFinishLaunching(_ notification: Notification) {
        if installer.offerMove() || handOffToRunningCopy() {
            return
        }
        installer.offerTrash()
        NSApp.mainMenu = Self.makeMainMenu()
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

    // applicationShouldHandleReopen opens the settings window when Sheepdog is opened again while it
    // runs, so a second open from Applications shows it is already there.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // handOffToRunningCopy reopens a Sheepdog that is already running from another path and quits this
    // one, so a second copy never puts a second Tug in the menu bar. It reports whether it handed off.
    private func handOffToRunningCopy() -> Bool {
        let me = NSRunningApplication.current
        guard let bundle = Bundle.main.bundleIdentifier,
              let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
                  .first(where: { $0.processIdentifier != me.processIdentifier }),
              let url = other.bundleURL else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
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

    // makeMainMenu builds the main menu that supplies the edit and close shortcuts. An accessory app
    // never shows a menu bar, but AppKit still routes key equivalents like Cmd+V through it.
    private static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let menu = NSMenu()
        for submenu in [NSMenu(title: "Sheepdog"), edit, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }
}

let app = NSApplication.shared
if let flag = CommandLine.arguments.firstIndex(of: DemoRenderer.argument) {
    let dir = CommandLine.arguments.dropFirst(flag + 1).first ?? "demo-frames"
    exit(MainActor.assumeIsolated { DemoRenderer.run(dir: dir) })
}
if let flag = CommandLine.arguments.firstIndex(of: DemoRenderer.stillsArgument) {
    let dir = CommandLine.arguments.dropFirst(flag + 1).first ?? "art"
    exit(MainActor.assumeIsolated { DemoRenderer.runStills(dir: dir) })
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
