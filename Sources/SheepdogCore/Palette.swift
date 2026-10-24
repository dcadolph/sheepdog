import Foundation

// RGB is an sRGB color with components from 0 to 1.
public struct RGB: Sendable, Equatable {
    // Red is the red component.
    public var red: Double
    // Green is the green component.
    public var green: Double
    // Blue is the blue component.
    public var blue: Double

    // black and white are the fallback label colors on an accent fill.
    public static let black = RGB(red: 0, green: 0, blue: 0)
    public static let white = RGB(red: 1, green: 1, blue: 1)

    // init creates a color from components.
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    // init parses a #rrggbb hex string, or returns nil when it is not one.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return nil
        }
        red = Double((value >> 16) & 0xff) / 255
        green = Double((value >> 8) & 0xff) / 255
        blue = Double(value & 0xff) / 255
    }

    // luminance is the WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    // contrast is the WCAG contrast ratio between this color and other, from 1 to 21.
    public func contrast(with other: RGB) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// Palette is the set of colors one theme gives the alert surfaces.
public struct Palette: Sendable, Equatable {
    // Background is behind the takeover.
    public var background: RGB
    // Surface is behind the pill and the hand-back card.
    public var surface: RGB
    // Text is the main text color.
    public var text: RGB
    // Muted is the color for hints and secondary lines.
    public var muted: RGB
    // Accent fills the main button and draws the ring.
    public var accent: RGB
    // Late marks a meeting that has already started.
    public var late: RGB

    // textMinimum is the WCAG AA contrast for normal text.
    public static let textMinimum = 4.5

    // onAccent is the label color on an accent fill: the background when it passes, else black or
    // white, whichever contrasts more. One of black or white always passes on any color.
    public var onAccent: RGB {
        if background.contrast(with: accent) >= Self.textMinimum {
            return background
        }
        return RGB.white.contrast(with: accent) >= RGB.black.contrast(with: accent) ? .white : .black
    }

    // accentText is the accent when it passes as small text on the background, else the text color.
    public var accentText: RGB {
        accent.contrast(with: background) >= Self.textMinimum ? accent : text
    }
}

// ThemeName is a color theme shared by name with moorings.
public enum ThemeName: String, Sendable, Codable, CaseIterable, Identifiable {
    case harbor
    case dragonsgale
    case greekFire
    case phosphor
    case redcoat
    case hussar
    case tyrian
    case ultramarine
    case verdigris
    case arrakis
    case bletchley

    // id identifies the theme in pickers.
    public var id: String { rawValue }

    // label is the theme's user-facing name.
    public var label: String {
        switch self {
        case .harbor: return "Harbor"
        case .dragonsgale: return "Dragonsgale"
        case .greekFire: return "Greek Fire"
        case .phosphor: return "Phosphor"
        case .redcoat: return "Redcoat"
        case .hussar: return "Hussar"
        case .tyrian: return "Tyrian"
        case .ultramarine: return "Ultramarine"
        case .verdigris: return "Verdigris"
        case .arrakis: return "Arrakis"
        case .bletchley: return "Bletchley"
        }
    }

    // palette is the theme's colors, in background, surface, text, muted, accent, late order.
    public var palette: Palette {
        switch self {
        case .harbor: return Self.make("#0f1012", "#0f1012", "#ffffff", "#aaa59b", "#f3e3b8", "#ff7361")
        case .dragonsgale: return Self.make("#0d0a08", "#1a1310", "#f4e6d8", "#b89c86", "#ff7a1a", "#ff7361")
        case .greekFire: return Self.make("#120805", "#24100a", "#ffe9c2", "#c99a6b", "#ffb000", "#ff7361")
        case .phosphor: return Self.make("#050a05", "#0b160b", "#b8ffb0", "#5fae5a", "#33ff33", "#ff7361")
        case .redcoat: return Self.make("#0e0c0c", "#1c1919", "#f4f1ee", "#a9a3a0", "#d6282f", "#ff7361")
        case .hussar: return Self.make("#1a0608", "#2b0c10", "#f3e3c0", "#c2a272", "#d4a63a", "#ff7361")
        case .tyrian: return Self.make("#140816", "#231027", "#f0e2f5", "#b597bf", "#b04cc8", "#ff7361")
        case .ultramarine: return Self.make("#060b1f", "#0e1736", "#e3e9ff", "#8e9cc9", "#4f78ff", "#ff7361")
        case .verdigris: return Self.make("#0a1614", "#12241f", "#dff3ec", "#86b3a5", "#43b39a", "#ff7361")
        case .arrakis: return Self.make("#0c0c0d", "#18181a", "#f5f5f2", "#a8a8a3", "#c07a44", "#ff7361")
        case .bletchley: return Self.make("#ece4cf", "#f6f0dd", "#1a1a17", "#5c5748", "#7a2e12", "#9c1c14")
        }
    }

    // make builds a palette from hex strings that are known to parse.
    private static func make(_ hexes: String...) -> Palette {
        let c = hexes.map { RGB(hex: $0)! }
        return Palette(background: c[0], surface: c[1], text: c[2], muted: c[3], accent: c[4], late: c[5])
    }
}
