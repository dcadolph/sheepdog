import AppKit
import SwiftUI

// KeyPanel is a borderless panel that can still take keyboard focus.
final class KeyPanel: NSPanel {
    // canBecomeKey lets the takeover receive Return for Join.
    override var canBecomeKey: Bool { true }
    // canBecomeMain lets the takeover act as the active window.
    override var canBecomeMain: Bool { true }
}

// AlertWindows owns the takeover panels and the countdown pill.
@MainActor
final class AlertWindows {
    // model is shared by every alert view.
    private let model: AlertModel
    // takeovers are the full-screen panels, one per display.
    private var takeovers: [NSPanel] = []
    // pill is the floating countdown panel.
    private var pill: NSPanel?

    // init binds the windows to a model.
    init(model: AlertModel) {
        self.model = model
    }

    // isShowingTakeover reports whether the full-screen alarm is up.
    var isShowingTakeover: Bool { !takeovers.isEmpty }

    // showTakeover covers every display, above full-screen apps and on every Space.
    func showTakeover() {
        hidePill()
        guard takeovers.isEmpty else {
            takeovers.first?.makeKeyAndOrderFront(nil)
            return
        }
        for screen in NSScreen.screens {
            let panel = KeyPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: TakeoverView(model: model))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            takeovers.append(panel)
        }
        NSApp.activate()
        takeovers.first?.makeKeyAndOrderFront(nil)
    }

    // hideTakeover removes the full-screen panels.
    func hideTakeover() {
        takeovers.forEach { $0.orderOut(nil) }
        takeovers.removeAll()
    }

    // showPill floats the countdown near the top center of the main display.
    func showPill() {
        let panel = pill ?? makePill()
        pill = panel
        if let host = panel.contentView as? NSHostingView<PillView> {
            let size = host.fittingSize
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10)
                panel.setFrame(NSRect(origin: origin, size: size), display: true)
            }
        }
        panel.orderFrontRegardless()
    }

    // hidePill removes the countdown panel.
    func hidePill() {
        pill?.orderOut(nil)
    }

    // hideAll removes every alert window.
    func hideAll() {
        hideTakeover()
        hidePill()
    }

    // makePill builds the countdown panel once.
    private func makePill() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        return panel
    }
}
