import AppKit
import SwiftUI

// KeyPanel is a borderless panel that can still take keyboard focus.
final class KeyPanel: NSPanel {
    // canBecomeKey lets the takeover receive Return for Join.
    override var canBecomeKey: Bool { true }
    // canBecomeMain lets the takeover act as the active window.
    override var canBecomeMain: Bool { true }
}

// AlertWindows owns the takeover panels, the countdown pill, the hand-back card, the notice card and
// the setup card.
@MainActor
final class AlertWindows {
    // model is shared by every alert view.
    private let model: AlertModel
    // takeovers are the full-screen panels, one per display.
    private var takeovers: [NSPanel] = []
    // pill is the floating countdown panel.
    private var pill: NSPanel?
    // handBack is the card that gives back a held note.
    private var handBack: NSPanel?
    // noticeCard is the card that tells the user something once.
    private var noticeCard: NSPanel?
    // setupCard is the card that says Tug may be missing a calendar.
    private var setupCard: NSPanel?
    // previousApp is the app that was in front before the takeover took focus.
    private var previousApp: NSRunningApplication?

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
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? nil : front
        NSApp.activate()
        takeovers.first?.makeKeyAndOrderFront(nil)
    }

    // hideTakeover removes the full-screen panels and hands focus back to the app that had it,
    // so the next click in that app is not spent bringing it forward.
    func hideTakeover() {
        guard !takeovers.isEmpty else {
            return
        }
        takeovers.forEach { $0.orderOut(nil) }
        takeovers.removeAll()
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    // forgetPreviousApp skips the focus hand-back, for when Join opens a meeting app that should stay in front.
    func forgetPreviousApp() {
        previousApp = nil
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

    // returnKeyFromPill gives typing back to the app in front after the note field had it. The pill
    // never activates Sheepdog, so that app is still frontmost and takes key again when the pill
    // briefly leaves the screen.
    func returnKeyFromPill() {
        guard let pill, pill.isKeyWindow else {
            return
        }
        pill.orderOut(nil)
        pill.orderFrontRegardless()
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            front.activate()
        }
    }

    // showHandBack floats the hand-back card in the top right of the menu bar display, sliding it in
    // the first time it appears. It stays on that display wherever the user is working, so it is
    // always in the same spot.
    func showHandBack() {
        let panel = handBack ?? makeCard(HandBackView(model: model))
        handBack = panel
        float(panel)
    }

    // hideHandBack removes the hand-back card.
    func hideHandBack() {
        handBack?.orderOut(nil)
    }

    // showNotice floats the notice card where the hand-back card goes. No two cards show together.
    func showNotice() {
        let panel = noticeCard ?? makeCard(NoticeCardView(model: model))
        noticeCard = panel
        float(panel)
    }

    // hideNotice removes the notice card.
    func hideNotice() {
        noticeCard?.orderOut(nil)
    }

    // showSetup floats the setup card where the hand-back card goes.
    func showSetup() {
        let panel = setupCard ?? makeCard(SetupCardView(model: model))
        setupCard = panel
        float(panel)
    }

    // hideSetup removes the setup card.
    func hideSetup() {
        setupCard?.orderOut(nil)
    }

    // float puts a card in the top right of the menu bar display, sliding it in when it appears, and
    // resizes it to its content while it stays up.
    private func float(_ panel: NSPanel) {
        let appearing = !panel.isVisible
        guard let host = panel.contentView, let screen = NSScreen.screens.first else {
            return
        }
        let size = host.fittingSize
        let visible = screen.visibleFrame
        let frame = NSRect(
            origin: NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 10),
            size: size
        )
        guard appearing else {
            panel.setFrame(frame, display: true)
            return
        }
        panel.setFrame(frame.offsetBy(dx: 0, dy: 12), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    // hideAll removes every alert window except the cards, which outlive alerts.
    func hideAll() {
        hideTakeover()
        hidePill()
    }

    // makePill builds the countdown panel once. It can take typing for the note field, but only
    // when the field itself is clicked, so Join and the close button leave focus where it was.
    private func makePill() -> NSPanel {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)
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

    // makeCard builds a floating card, which never takes focus.
    private func makeCard<Content: View>(_ view: Content) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
