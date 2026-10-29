import AppKit

import SheepdogCore

// TugDrawing is one drawing of Tug and where it rests.
struct TugDrawing {
    // image is the menu bar template of the drawing.
    let image: NSImage
    // rect is where the drawing is drawn at rest.
    let rect: CGRect
}

// TugFigure is what the stage animates: the drawings Tug passes through and where each rests.
struct TugFigure {
    // drawings holds each drawing the animation shows.
    let drawings: [TugShape: TugDrawing]
    // wags reports whether the sitting tail is drawn apart from the body so it can swing.
    let wags: Bool
    // jump is how far right and up a pose's full drift and lift move Tug, in points.
    let jump: CGVector

    // wake is the hop Tug makes when he wakes.
    static let wake = CGVector(dx: 0, dy: 5)
    // exit is the leap Tug makes when he quits, high enough to clear the top of the screen.
    static let exit = CGVector(dx: 26, dy: 34)

    // moved returns the figure with every drawing shifted by offset.
    func moved(by offset: CGVector) -> TugFigure {
        TugFigure(
            drawings: drawings.mapValues {
                TugDrawing(image: $0.image, rect: $0.rect.offsetBy(dx: offset.dx, dy: offset.dy))
            },
            wags: wags, jump: jump
        )
    }
}

// TugStage plays one of Tug's animations over the menu bar icon in a clear panel, so he looks to move
// on the screen itself, then calls done.
@MainActor
final class TugStage {
    // below is how far the panel reaches under the menu bar.
    static let below: CGFloat = 18
    // right is how far the panel reaches right of the status item, for the leap.
    static let right: CGFloat = 40
    // grace is how long past the animation done runs anyway, should the timer stall.
    static let grace = 0.5

    // panel shows the animation, nil until play.
    private var panel: NSPanel?
    // timer redraws the animation while it plays.
    private var timer: Timer?
    // done runs once the animation ends, nil once it ran.
    private var done: (@MainActor () -> Void)?

    // play shows the animation over item, the status item's frame on screen, with figure in screen
    // coordinates, drawing in the appearance of the menu bar, then calls done.
    func play(
        _ motion: @escaping @Sendable (Double) -> TugPose, seconds: Double, over item: CGRect, figure: TugFigure,
        appearance: NSAppearance, done: @escaping @MainActor () -> Void
    ) {
        let rect = CGRect(
            x: item.minX - 8, y: item.minY - Self.below,
            width: item.width + 8 + Self.right, height: item.height + Self.below
        )
        let p = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = TugStageView(
            frame: CGRect(origin: .zero, size: rect.size),
            figure: figure.moved(by: CGVector(dx: -rect.minX, dy: -rect.minY)), pose: motion(0)
        )
        view.appearance = appearance
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
        self.done = done
        let start = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) / seconds
                view.pose = motion(elapsed)
                view.needsDisplay = true
                if elapsed >= 1 {
                    self?.finish()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + Self.grace) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    // finish stops the animation and runs done, once.
    private func finish() {
        guard let done else {
            return
        }
        self.done = nil
        timer?.invalidate()
        panel?.orderOut(nil)
        done()
    }
}

// TugStageView draws one pose of Tug in the menu bar's ink, with nothing behind him.
final class TugStageView: NSView {
    // figure is what is drawn and where.
    private let figure: TugFigure
    // pose is the frame to draw.
    var pose: TugPose

    // init builds the view for a figure, showing pose.
    init(frame: CGRect, figure: TugFigure, pose: TugPose) {
        self.figure = figure
        self.pose = pose
        super.init(frame: frame)
    }

    // init(coder:) is not used.
    required init?(coder: NSCoder) { nil }

    // draw paints the pose in the label color.
    override func draw(_ dirtyRect: NSRect) {
        Self.draw(pose, figure, ink: .labelColor, in: bounds)
    }

    // draw paints pose of figure in ink inside bounds, into the current context. The body moves as one
    // about the ground, and the sitting tail swings about its root.
    static func draw(_ pose: TugPose, _ figure: TugFigure, ink: NSColor, in bounds: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        ctx.saveGState()
        ctx.setAlpha(pose.fade)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if let drawing = figure.drawings[pose.shape] {
            ctx.saveGState()
            ctx.concatenate(body(pose, jump: figure.jump, in: drawing.rect))
            if pose.shape == .sitting, figure.wags {
                drawWagging(drawing.image, in: drawing.rect, tail: pose.tail, ctx: ctx)
            } else {
                drawing.image.draw(in: drawing.rect)
            }
            if pose.shape == .sitting, pose.bark > 0 {
                drawBark(in: drawing.rect, opacity: pose.bark)
            }
            ctx.restoreGState()
        }
        ink.setFill()
        bounds.fill(using: .sourceIn)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // body returns the move of Tug's body for pose: lifted and drifted across jump, and squashed toward
    // the ground under rect.
    private static func body(_ pose: TugPose, jump: CGVector, in rect: CGRect) -> CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: jump.dx * pose.drift + rect.midX, y: jump.dy * pose.lift + rect.minY)
            .scaledBy(x: 1 + 0.6 * pose.squash, y: 1 - pose.squash)
            .translatedBy(x: -rect.midX, y: -rect.minY)
    }

    // tailShare is how much of the sitting glyph's width, from the left, holds only the tail, and
    // tailHeight how much of the dog's height, from the ground. tailRoot is where the tail meets the
    // body, as shares of the dog's width and height.
    private static let tailShare: CGFloat = 0.197, tailHeight: CGFloat = 0.42
    private static let tailRoot = CGPoint(x: 0.2, y: 0.09)

    // barkFrom is the point in front of the sitting glyph's open mouth the bark lines fan out from, in
    // the glyph's pixels from its bottom left. barkRays are the lines' angles in degrees, and barkReach
    // where each starts and ends, in pixels from barkFrom.
    private static let barkFrom = CGPoint(x: 250, y: 208)
    private static let barkRays: [CGFloat] = [52, 14, -24]
    private static let barkReach: (start: CGFloat, end: CGFloat) = (26, 60)

    // drawBark draws the three bark lines in front of the mouth of the sitting glyph in rect. Like the
    // tail, they are placed from the glyph's width, so an outfit's headroom above him is ignored.
    private static func drawBark(in rect: CGRect, opacity: Double) {
        let scale = rect.width / 315
        let path = NSBezierPath()
        for degrees in barkRays {
            let angle = degrees * .pi / 180
            for (reach, move) in [(barkReach.start, true), (barkReach.end, false)] {
                let point = CGPoint(
                    x: rect.minX + (barkFrom.x + reach * cos(angle)) * scale,
                    y: rect.minY + (barkFrom.y + reach * sin(angle)) * scale
                )
                move ? path.move(to: point) : path.line(to: point)
            }
        }
        path.lineWidth = 1
        path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(opacity).setStroke()
        path.stroke()
    }

    // drawWagging draws the sitting glyph in rect with its tail turned tail degrees about the root.
    // The dog's height is taken from the glyph's width, so an outfit's headroom above him is ignored.
    private static func drawWagging(_ image: NSImage, in rect: CGRect, tail: Double, ctx: CGContext) {
        let dog = rect.width * 256 / 315
        let tailRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * tailShare, height: dog * tailHeight)
        ctx.saveGState()
        let rest = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
        rest.append(NSBezierPath(rect: tailRect))
        rest.windingRule = .evenOdd
        rest.addClip()
        image.draw(in: rect)
        ctx.restoreGState()
        ctx.saveGState()
        let root = CGPoint(x: rect.minX + tailRoot.x * rect.width, y: rect.minY + tailRoot.y * dog)
        ctx.translateBy(x: root.x, y: root.y)
        ctx.rotate(by: tail * .pi / 180)
        ctx.translateBy(x: -root.x, y: -root.y)
        NSBezierPath(rect: tailRect).addClip()
        image.draw(in: rect)
        ctx.restoreGState()
    }
}
