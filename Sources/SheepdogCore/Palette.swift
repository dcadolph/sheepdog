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
    // Collar recolors Tug's collar, or is nil to keep the drawing's own collar.
    public var collar: RGB?

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

// ThemeName is a collar for Tug. Each one colors his collar and the alert surfaces.
public enum ThemeName: String, Sendable, Codable, CaseIterable, Identifiable {
    case wolf
    case blackDiamond
    case goldenSpark
    case rubie
    case lightning
    case thunder
    case strawhat

    // id identifies the theme in pickers.
    public var id: String { rawValue }

    // label is the theme's user-facing name.
    public var label: String {
        switch self {
        case .wolf: return "Wolf"
        case .blackDiamond: return "Black Diamond"
        case .goldenSpark: return "Golden Spark"
        case .rubie: return "Rubie"
        case .lightning: return "Lightning"
        case .thunder: return "Thunder"
        case .strawhat: return "Strawhat"
        }
    }

    // palette is the theme's colors: the collar, then background, surface, text, muted, accent, late.
    public var palette: Palette {
        switch self {
        case .wolf:
            return Self.make(nil, "#0f1012", "#0f1012", "#ffffff", "#aaa59b", "#f3e3b8", "#ff7361")
        case .blackDiamond:
            return Self.make("#2a2a2a", "#0e0d0a", "#1a1812", "#fff8e6", "#b3a88a", "#d4af37", "#ff7361")
        case .goldenSpark:
            return Self.make("#2f9e4f", "#0b100c", "#142019", "#fff6d8", "#b0a57f", "#e8b923", "#ff7361")
        case .rubie:
            return Self.make("#c8102e", "#f4f1ee", "#fbf9f7", "#111111", "#5a5552", "#111111", "#b3261e")
        case .lightning:
            return Self.make("#2457e6", "#0a0d1a", "#131a30", "#fffbe0", "#b3ad8a", "#ffd400", "#ff7361")
        case .thunder:
            return Self.make("#1f3fbf", "#07141a", "#0e222b", "#e6fbff", "#8fb8c2", "#5fd4e6", "#ff7361")
        case .strawhat:
            return Self.make("#d22b2b", "#13100c", "#211c15", "#f7efe2", "#ad9f88", "#d9c7a3", "#ff7361")
        }
    }

    // make builds a palette from a collar hex, or nil for the drawing's own, and hex strings that are known
    // to parse.
    private static func make(_ collar: String?, _ hexes: String...) -> Palette {
        let c = hexes.map { RGB(hex: $0)! }
        return Palette(
            background: c[0], surface: c[1], text: c[2], muted: c[3], accent: c[4], late: c[5],
            collar: collar.map { RGB(hex: $0)! }
        )
    }
}
