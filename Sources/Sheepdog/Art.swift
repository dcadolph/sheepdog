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

    // body draws the image scaled to fit its frame.
    var body: some View {
        if let image = Art.image(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "dog.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
        }
    }
}
