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

// ThemeName is a collar for Tug. Each one colors his collar and the alert surfaces. The custom collar
// takes its colors from AlertSettings.customColors.
public enum ThemeName: String, Sendable, Codable, CaseIterable, Identifiable {
    case wolf
    case blackDiamond
    case goldenSpark
    case rubie
    case lightning
    case thunder
    case strawhat
    case grapes
    case bubblegum
    case berserker
    case pickleJuice
    case trunk
    case custom

    // presets are the built-in collars, every case but custom.
    public static var presets: [ThemeName] { allCases.filter { $0 != .custom } }

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
        case .grapes: return "Grapes"
        case .bubblegum: return "Bubblegum"
        case .berserker: return "Berserker"
        case .pickleJuice: return "PickleJuice"
        case .trunk: return "Trunk"
        case .custom: return "Custom"
        }
    }

    // palette is the theme's colors: the collar, then background, surface, text, muted, accent, late. For
    // custom it is the default custom colors; AlertSettings.palette gives the user's own.
    public var palette: Palette {
        switch self {
        case .wolf:
            return Self.make(nil, "#0f1012", "#0f1012", "#ffffff", "#aaa59b", "#f3e3b8", "#ff7361")
        case .blackDiamond:
            return Self.make("#2a2a2a", "#0c0c0c", "#1c1c1c", "#ffffff", "#b5b5b5", "#f5c518", "#ff7361")
        case .goldenSpark:
            return Self.make("#2f9e4f", "#0c2a18", "#143a24", "#fff6d8", "#a9c7a3", "#f2c230", "#ff8a75")
        case .rubie:
            return Self.make("#c8102e", "#f4f1ee", "#fbf9f7", "#111111", "#5a5552", "#111111", "#b3261e")
        case .lightning:
            return Self.make("#ffd400", "#0a0d1a", "#131a30", "#fffbe0", "#b3ad8a", "#4f8bff", "#ff7361")
        case .thunder:
            return Self.make("#1f3fbf", "#07141a", "#0e222b", "#e6fbff", "#8fb8c2", "#5fd4e6", "#ff7361")
        case .strawhat:
            return Self.make("#d22b2b", "#13100c", "#211c15", "#f7efe2", "#ad9f88", "#d9c7a3", "#ff7361")
        case .grapes:
            return Self.make("#7b2cbf", "#16081f", "#261236", "#f7eeff", "#c3a9db", "#c77dff", "#ff8a75")
        case .bubblegum:
            return Self.make("#d6336c", "#1a0a12", "#2c1222", "#fff0f6", "#d6a6be", "#ff5fa2", "#ffb347")
        case .berserker:
            return Self.make("#5c3317", "#1a0f08", "#2c1b10", "#fff1e0", "#cfa98a", "#ff8c1a", "#ff6b6b")
        case .pickleJuice:
            return Self.make("#8fd400", "#10130a", "#1c2112", "#f4ffe0", "#b4c29a", "#c6f432", "#ff7361")
        case .trunk:
            return Self.make("#ff8c42", "#f7ecd6", "#fff8ea", "#14181c", "#5c564a", "#7a4b1e", "#b3261e")
        case .custom:
            return CustomColors().palette
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
