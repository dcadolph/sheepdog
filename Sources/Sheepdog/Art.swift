import AppKit
import SwiftUI

import SheepdogCore

// Art loads Tug's drawings from the app bundle's resources.
@MainActor
enum Art {
    // cache holds each drawing after its first load.
    private static var cache: [String: NSImage] = [:]

    // image returns a bundled PNG drawing, or nil when the app runs outside its bundle.
    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        cache[name] = image
        return image
    }

    // collarBase is the average luminance of the drawn collar, used to keep its shading when recolored.
    private static let collarBase = 127.0

    // tinted returns a bundled drawing with the blue collar recolored to the collar color.
    static func tinted(_ name: String, collar: RGB) -> NSImage? {
        let key = "\(name)#\(collar.red),\(collar.green),\(collar.blue)"
        if let cached = cache[key] {
            return cached
        }
        guard let source = image(name),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(
                  data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                  bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let data = ctx.data
        else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: cg.width * cg.height * 4)
        for i in stride(from: 0, to: cg.width * cg.height * 4, by: 4) {
            let a = Double(bytes[i + 3]) / 255
            if a < 0.8 {
                continue
            }
            let r = Double(bytes[i]) / a, g = Double(bytes[i + 1]) / a, b = Double(bytes[i + 2]) / a
            if b <= r + 30 || b < g {
                continue
            }
            let scale = (0.299 * r + 0.587 * g + 0.114 * b) / collarBase
            bytes[i] = UInt8(min(255, collar.red * 255 * scale) * a)
            bytes[i + 1] = UInt8(min(255, collar.green * 255 * scale) * a)
            bytes[i + 2] = UInt8(min(255, collar.blue * 255 * scale) * a)
        }
        guard let out = ctx.makeImage() else {
            return nil
        }
        let image = NSImage(cgImage: out, size: source.size)
        cache[key] = image
        return image
    }

    // glyph returns the menu bar template for a stage, sized for the menu bar.
    static func glyph(for stage: Stage) -> NSImage? {
        let name: String
        switch stage {
        case .idle:
            name = "glyph-idle"
        case .warning:
            name = "glyph-warning"
        case .takeover:
            name = "glyph-takeover"
        }
        guard let image = image(name)?.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(width: 18 * image.size.width / image.size.height, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Sheepdog"
        return image
    }

    // poseGlyph returns Tug in one of his animation drawings as a template, at the sitting glyph's
    // scale, where 256 pixels make 18pt, so every drawing is the same size dog. Sitting is the idle glyph.
    static func poseGlyph(_ shape: TugShape) -> NSImage? {
        let name: String
        switch shape {
        case .lying:
            name = "glyph-nap"
        case .dozing:
            name = "glyph-doze"
        case .sitting:
            name = "glyph-idle"
        case .bow:
            name = "glyph-bow"
        case .leap:
            name = "glyph-leap"
        }
        guard let image = image(name)?.copy() as? NSImage,
              let height = image.representations.first?.pixelsHigh,
              let width = image.representations.first?.pixelsWide
        else {
            return nil
        }
        image.size = NSSize(width: CGFloat(width) * 18 / 256, height: CGFloat(height) * 18 / 256)
        image.isTemplate = true
        image.accessibilityDescription = "Sheepdog"
        return image
    }

    // napGlyph returns Tug napping for the menu bar, lying with Zs over him or dozing, on a canvas as
    // tall as the sitting glyph with him on its floor, so he lies on the same ground he sits on. Both nap drawings share
    // the canvas width with Tug at its right edge, so swapping them never moves the menu bar.
    static func napGlyph(_ shape: TugShape = .lying) -> NSImage? {
        guard let dog = poseGlyph(shape), let lying = poseGlyph(.lying), let dozing = poseGlyph(.dozing) else {
            return nil
        }
        let width = max(lying.size.width, dozing.size.width)
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            dog.draw(in: NSRect(origin: NSPoint(x: width - dog.size.width, y: 0), size: dog.size))
            if shape == .lying {
                drawZs(width: width)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sheepdog, napping"
        return image
    }

    // sleepZs are the Zs over a sleeping Tug, smallest first: point size, center as a share of the
    // canvas width, and baseline. They rise over his head and stay inside the 18pt canvas.
    private static let sleepZs: [(size: CGFloat, x: CGFloat, baseline: CGFloat)] = [
        (4.5, 0.64, 8.4), (5.5, 0.77, 10.6), (6.5, 0.91, 12.8),
    ]

    // drawZs draws the sleep Zs on a nap canvas width points wide.
    private static func drawZs(width: CGFloat) {
        for z in sleepZs {
            let base = NSFont.systemFont(ofSize: z.size, weight: .heavy)
            let rounded = base.fontDescriptor.withDesign(.rounded)
            let font = rounded.flatMap { NSFont(descriptor: $0, size: z.size) } ?? base
            let text = NSAttributedString(string: "z", attributes: [.font: font, .foregroundColor: NSColor.black])
            text.draw(at: NSPoint(x: z.x * width - text.size().width / 2, y: z.baseline))
        }
    }

}

// TugImage shows a bundled drawing of Tug, falling back to the system dog symbol.
struct TugImage: View {
    // name is the drawing's file name without the extension.
    let name: String
    // palette is the theme whose collar Tug wears, or nil for the current theme.
    var palette: Palette?
    // outfit is the costume drawn over Tug, or nil for none.
    var outfit: Outfit? = Theme.outfit

    // body draws the image scaled to fit its frame, with the theme's collar and the outfit on top.
    var body: some View {
        let themed = (palette ?? Theme.palette).collar.map { Art.tinted(name, collar: $0) } ?? Art.image(name)
        if let image = themed {
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                if let outfit, let prop = Art.image("outfit-\(outfit.asset)\(name == "tug-head" ? "-head" : "")") {
                    Image(nsImage: prop)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
        } else {
            Image(systemName: "dog.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
        }
    }
}
