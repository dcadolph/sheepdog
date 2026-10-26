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

    // tinted returns a bundled drawing with the blue collar recolored to the accent.
    static func tinted(_ name: String, accent: RGB) -> NSImage? {
        let key = "\(name)#\(accent.red),\(accent.green),\(accent.blue)"
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
            bytes[i] = UInt8(min(255, accent.red * 255 * scale) * a)
            bytes[i + 1] = UInt8(min(255, accent.green * 255 * scale) * a)
            bytes[i + 2] = UInt8(min(255, accent.blue * 255 * scale) * a)
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

    // outfitGlyph returns a stage's menu bar template with the outfit's prop on Tug's head. The prop art
    // has the glyph's width and 40 more rows of headroom, and a thin gap is cut from the dog around it so
    // the prop reads as its own shape at 18pt.
    static func outfitGlyph(for stage: Stage, outfit: Outfit) -> NSImage? {
        guard let dog = glyph(for: stage), let source = image("glyph-idle"),
              let prop = image("outfit-\(outfit.asset)-glyph")
        else {
            return nil
        }
        let dogRect = NSRect(origin: .zero, size: source.size)
        let propRect = NSRect(origin: .zero, size: prop.size)
        let canvas = NSImage(size: prop.size, flipped: false) { _ in
            dog.draw(in: dogRect)
            for radius in [4.0, 8.0] {
                for step in 0..<16 {
                    let angle = Double(step) * .pi / 8
                    prop.draw(
                        in: propRect.offsetBy(dx: radius * cos(angle), dy: radius * sin(angle)),
                        from: .zero, operation: .destinationOut, fraction: 1
                    )
                }
            }
            prop.draw(in: propRect)
            return true
        }
        canvas.size = NSSize(
            width: dog.size.width, height: dog.size.height * prop.size.height / source.size.height
        )
        canvas.isTemplate = true
        canvas.accessibilityDescription = "Sheepdog, dressed for \(outfit.label)"
        return canvas
    }

    // napGlyph returns the idle glyph with a small zzz above Tug's head, so a nap shows in the menu bar.
    static func napGlyph() -> NSImage? {
        guard let dog = glyph(for: .idle),
              let zzz = NSImage(systemSymbolName: "zzz", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        else {
            return nil
        }
        let size = NSSize(width: dog.size.width + zzz.size.width - 2, height: dog.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            dog.draw(in: NSRect(origin: .zero, size: dog.size))
            zzz.draw(in: NSRect(
                x: size.width - zzz.size.width, y: size.height - zzz.size.height,
                width: zzz.size.width, height: zzz.size.height
            ))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sheepdog, napping"
        return image
    }
}

// TugImage shows a bundled drawing of Tug, falling back to the system dog symbol.
struct TugImage: View {
    // name is the drawing's file name without the extension.
    let name: String
    // accent is the collar color, or nil for the current theme's accent.
    var accent: RGB?
    // outfit is the costume drawn over Tug, or nil for none.
    var outfit: Outfit? = Theme.outfit

    // body draws the image scaled to fit its frame, with the collar in the accent and the outfit on top.
    var body: some View {
        let accent = accent ?? Theme.palette.accent
        let themed = accent == ThemeName.harbor.palette.accent ? Art.image(name) : Art.tinted(name, accent: accent)
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
