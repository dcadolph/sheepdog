import AppKit
import SwiftUI

import SheepdogCore

// DemoRenderer draws the README demo from the real pill and takeover views over a made-up
// desktop, so no real screen, calendar or account is ever captured.
@MainActor
enum DemoRenderer {
    // argument is the launch argument that renders the demo frames instead of running the app.
    static let argument = "--render-demo"
    // stillsArgument is the launch argument that renders the README stills instead of running the app.
    static let stillsArgument = "--render-stills"
    // size is the scene size in points, a 16:10 laptop screen.
    static let size = CGSize(width: 1440, height: 900)
    // fps is how many frames are drawn per second of demo.
    static let fps = 12.0

    // Beat is one stretch of the demo with a fixed surface and a moving clock.
    struct Beat {
        // duration is how long the beat lasts in seconds.
        let duration: Double
        // stage is the surface on screen.
        let stage: Stage
        // untilStart is the countdown, in seconds, when the beat begins.
        let untilStart: TimeInterval
        // snoozesLeft is what the snooze button offers.
        let snoozesLeft: Int
        // snoozeLength is the next snooze's length in seconds.
        let snoozeLength: TimeInterval
        // cursor moves from the first point to the second over the beat, in scene points.
        let cursor: (from: CGPoint, to: CGPoint)
        // clickAt is the fraction of the beat when the cursor clicks, if it does.
        let clickAt: Double?
    }

    // rest is where the cursor sits while the user works.
    static let rest = CGPoint(x: 560, y: 520)
    // snoozeButton is the center of the takeover's Snooze button.
    static let snoozeButton = CGPoint(x: 603, y: 674)
    // joinButton is the center of the takeover's Join button.
    static let joinButton = CGPoint(x: 720, y: 608)

    // beats is the demo: warning pill, takeover, snooze, takeover at the start, join.
    static let beats: [Beat] = [
        Beat(duration: 3, stage: .warning, untilStart: 125, snoozesLeft: 2, snoozeLength: 60,
             cursor: (rest, rest), clickAt: nil),
        Beat(duration: 2, stage: .takeover, untilStart: 60, snoozesLeft: 2, snoozeLength: 60,
             cursor: (rest, rest), clickAt: nil),
        Beat(duration: 1.5, stage: .takeover, untilStart: 58, snoozesLeft: 2, snoozeLength: 60,
             cursor: (rest, snoozeButton), clickAt: 0.85),
        Beat(duration: 2.5, stage: .warning, untilStart: 56, snoozesLeft: 1, snoozeLength: 60,
             cursor: (snoozeButton, rest), clickAt: nil),
        Beat(duration: 2, stage: .takeover, untilStart: 0, snoozesLeft: 1, snoozeLength: 30,
             cursor: (rest, rest), clickAt: nil),
        Beat(duration: 1.5, stage: .takeover, untilStart: -2, snoozesLeft: 1, snoozeLength: 30,
             cursor: (rest, joinButton), clickAt: 0.85),
        Beat(duration: 1.5, stage: .idle, untilStart: -4, snoozesLeft: 1, snoozeLength: 30,
             cursor: (joinButton, joinButton), clickAt: nil),
    ]

    // run writes numbered PNG frames into dir and returns a process exit code.
    static func run(dir: String) -> Int32 {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("demo dir create failed: \(error)\n".utf8))
            return 1
        }
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let model = AlertModel()
        var index = 0
        for beat in beats {
            let count = Int((beat.duration * fps).rounded())
            for frame in 0..<count {
                let progress = Double(frame) / Double(max(count - 1, 1))
                let start = base.addingTimeInterval(beat.untilStart)
                model.meeting = Meeting(
                    id: "demo",
                    title: "Design review",
                    start: start,
                    end: start.addingTimeInterval(1800),
                    link: JoinLinkFinder.find(in: "https://zoom.us/j/5551234567")
                )
                model.now = base.addingTimeInterval(Double(frame) / fps)
                model.snoozesLeft = beat.snoozesLeft
                model.snoozeLength = beat.snoozeLength
                let cursor = mix(beat.cursor.from, beat.cursor.to, ease(min(progress / (beat.clickAt ?? 1), 1)))
                let pressed = beat.clickAt.map { progress >= $0 && progress < $0 + 0.12 } ?? false
                let scene = DemoScene(model: model, stage: beat.stage, cursor: cursor, pressed: pressed)
                    .frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: scene)
                renderer.scale = 1
                guard let image = renderer.cgImage else {
                    FileHandle.standardError.write(Data("demo render failed: frame \(index)\n".utf8))
                    return 1
                }
                let url = out.appendingPathComponent(String(format: "frame-%04d.png", index))
                guard write(image, to: url) else {
                    FileHandle.standardError.write(Data("demo write failed: \(url.path)\n".utf8))
                    return 1
                }
                index += 1
            }
        }
        FileHandle.standardError.write(Data("demo: \(index) frames in \(out.path)\n".utf8))
        return 0
    }

    // Still is one README image: a scene, a crop of it in scene points, and a file name.
    struct Still {
        // name is the PNG file name.
        let name: String
        // scene is the full frame the still is cut from.
        let scene: DemoScene
        // crop is the part of the scene kept, in scene points.
        let crop: CGRect
    }

    // stills returns the README images: the takeover asking to hold a place, the pill holding a
    // note, and the hand-back card with more waiting behind it.
    static func stills() -> [Still] {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let meeting = Meeting(
            id: "demo",
            title: "Design review",
            start: base.addingTimeInterval(40),
            end: base.addingTimeInterval(1840),
            link: JoinLinkFinder.find(in: "https://zoom.us/j/5551234567")
        )
        let note = "Retry tests for the upload queue"

        let takeover = AlertModel()
        takeover.meeting = meeting
        takeover.now = base
        takeover.snoozesLeft = 2
        takeover.askPlace = true

        let pill = AlertModel()
        pill.meeting = meeting
        pill.now = base.addingTimeInterval(-85)
        pill.snoozesLeft = 2
        pill.heldNote = note

        let card = AlertModel()
        card.handBack = HeldPlace(id: "demo", title: "Design review", note: note, savedAt: base, meetingEnd: base)
        card.handBackCount = 3

        let top = CGRect(x: 420, y: 0, width: 600, height: 116)
        return [
            Still(name: "takeover.png",
                  scene: DemoScene(model: takeover, stage: .takeover, cursor: rest, pressed: false),
                  crop: CGRect(origin: .zero, size: size)),
            Still(name: "pill.png",
                  scene: DemoScene(model: pill, stage: .warning, cursor: rest, pressed: false),
                  crop: top),
            Still(name: "handback.png",
                  scene: DemoScene(model: card, stage: .idle, cursor: rest, pressed: false, handBack: true),
                  crop: CGRect(x: size.width - 440, y: 0, width: 440, height: 180)),
        ]
    }

    // runStills writes the README stills into dir at twice scene resolution and returns a process exit code.
    static func runStills(dir: String) -> Int32 {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        for still in stills() {
            let renderer = ImageRenderer(content: still.scene.frame(width: size.width, height: size.height))
            renderer.scale = 2
            let crop = CGRect(x: still.crop.minX * 2, y: still.crop.minY * 2,
                              width: still.crop.width * 2, height: still.crop.height * 2)
            guard let image = renderer.cgImage?.cropping(to: crop) else {
                FileHandle.standardError.write(Data("still render failed: \(still.name)\n".utf8))
                return 1
            }
            let url = out.appendingPathComponent(still.name)
            guard write(image, to: url) else {
                FileHandle.standardError.write(Data("still write failed: \(url.path)\n".utf8))
                return 1
            }
        }
        return 0
    }

    // write saves a frame as PNG.
    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? data.write(to: url)) != nil
    }

    // ease is a smooth in-and-out curve for cursor moves.
    private static func ease(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    // mix interpolates between two points.
    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

// DemoScene is one demo frame: a made-up desktop, the alert surface for the stage, and a cursor.
struct DemoScene: View {
    // model supplies the meeting and countdown to the real alert views.
    let model: AlertModel
    // stage picks which surface is up.
    let stage: Stage
    // cursor is the pointer position in scene points.
    let cursor: CGPoint
    // pressed draws the pointer mid-click.
    let pressed: Bool
    // handBack draws the hand-back card at the top right of the menu bar display.
    var handBack = false

    // body stacks the desktop, the alert and the pointer.
    var body: some View {
        ZStack(alignment: .topLeading) {
            DemoDesktop(stage: stage)
            if stage == .warning {
                PillView(model: model)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34)
            }
            if stage == .takeover {
                TakeoverView(model: model)
            }
            if handBack {
                HandBackView(model: model)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 38)
                    .padding(.trailing, 16)
            }
            Image(systemName: "cursorarrow")
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .scaleEffect(pressed ? 0.82 : 1, anchor: .topLeading)
                .offset(x: cursor.x - 6, y: cursor.y - 4)
        }
        .frame(width: DemoRenderer.size.width, height: DemoRenderer.size.height)
        .clipped()
    }
}

// DemoDesktop is a plain dark desktop with a menu bar and a generic document window.
struct DemoDesktop: View {
    // stage picks the menu bar glyph.
    let stage: Stage

    // body draws the wallpaper, menu bar and window.
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.09), Color(red: 0.17, green: 0.19, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if let glyph = Art.glyph(for: stage) {
                        Image(nsImage: glyph)
                            .renderingMode(.template)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 26)
                .background(.white.opacity(0.06))
                Spacer()
            }
            window
                .padding(.top, 120)
        }
    }

    // window is a generic document with placeholder lines.
    private var window: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                    Circle().fill(color).frame(width: 12, height: 12)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color(red: 0.2, green: 0.21, blue: 0.22))
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array([0.72, 0.9, 0.55, 0.82, 0.64, 0.88, 0.4, 0.7].enumerated()), id: \.offset) { _, width in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.25, green: 0.27, blue: 0.28))
                        .frame(width: 780 * width, height: 12)
                }
            }
            .padding(36)
            Spacer()
        }
        .frame(width: 900, height: 680)
        .background(Color(red: 0.14, green: 0.15, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}
