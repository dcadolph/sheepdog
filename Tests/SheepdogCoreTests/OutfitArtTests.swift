#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SheepdogCore

// outfitArtDir is the repo's art folder, found from this file's path.
let outfitArtDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("art")

// OutfitFile is one outfit drawing the app bundles, with the canvas it must have.
struct OutfitFile: Sendable, CustomTestStringConvertible {
    // Name is the file name without the extension.
    let name: String
    // Width is the canvas width in pixels.
    let width: Int
    // Height is the canvas height in pixels.
    let height: Int

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// outfitFiles lists the three drawings every outfit needs: the full Tug overlay, the head overlay and
// the menu bar prop.
let outfitFiles: [OutfitFile] = Outfit.allCases.flatMap { outfit in
    [
        OutfitFile(name: "outfit-\(outfit.asset)", width: 704, height: 704),
        OutfitFile(name: "outfit-\(outfit.asset)-head", width: 256, height: 256),
        OutfitFile(name: "outfit-\(outfit.asset)-glyph", width: 315, height: 296),
    ]
}

// loadRGBA reads a PNG into unpremultiplied RGBA bytes.
func loadRGBA(_ url: URL) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        return nil
    }
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let ctx = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (width, height, bytes) : nil
}

// collarBluePixels counts pixels the app's collar recolor would tint: opaque enough and clearly blue.
func collarBluePixels(_ bytes: [UInt8]) -> Int {
    var count = 0
    for i in stride(from: 0, to: bytes.count, by: 4) {
        let a = Double(bytes[i + 3]) / 255
        if a < 0.8 {
            continue
        }
        let r = Double(bytes[i]) / a, g = Double(bytes[i + 1]) / a, b = Double(bytes[i + 2]) / a
        if b > r + 30 && b >= g {
            count += 1
        }
    }
    return count
}

// outfitArtIsBundledAndUntinted checks each outfit drawing exists at its canvas size and carries no
// collar blue, so the collar recolor never tints a prop.
@Test(arguments: outfitFiles)
func outfitArtIsBundledAndUntinted(_ file: OutfitFile) throws {
    let image = try #require(loadRGBA(outfitArtDir.appendingPathComponent("\(file.name).png")))
    #expect(image.width == file.width)
    #expect(image.height == file.height)
    #expect(collarBluePixels(image.bytes) == 0)
}

// collarBluePixelsFindsTheCollar checks the predicate against Tug's own drawing, whose collar is blue.
@Test func collarBluePixelsFindsTheCollar() throws {
    let tug = try #require(loadRGBA(outfitArtDir.appendingPathComponent("tug.png")))
    #expect(collarBluePixels(tug.bytes) > 1000)
}
#endif
