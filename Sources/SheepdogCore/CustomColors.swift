import Foundation

// CustomColors are the colors a user picks for the Custom collar. Two are required and two are
// optional; the rest of the palette is derived so it always reads.
public struct CustomColors: Sendable, Codable, Equatable {
    // Background is the #rrggbb behind the takeover.
    public var background: String = "#0f1012"
    // Accent is the #rrggbb of the ring and buttons.
    public var accent: String = "#f3e3b8"
    // Collar is the #rrggbb of Tug's collar, or nil to keep the drawing's own.
    public var collar: String?
    // Late is the #rrggbb that marks a meeting already started, or nil for the default for the background.
    public var late: String?

    // Slot names a picked color that the derivation may have moved.
    public enum Slot: Sendable, Hashable {
        case background
        case accent
        case late
    }

    // Resolved is a derived palette with the slots that were moved to keep the text readable.
    public struct Resolved: Sendable, Equatable {
        // Palette is the full set of colors.
        public var palette: Palette
        // Adjusted lists the picked colors that were moved.
        public var adjusted: Set<Slot>
    }

    // init creates the defaults, which are Wolf's colors.
    public init() {}

    // init creates custom colors from hex strings.
    public init(background: String, accent: String, collar: String? = nil, late: String? = nil) {
        self.background = background
        self.accent = accent
        self.collar = collar
        self.late = late
    }

    // palette is the derived palette, ignoring which colors moved.
    public var palette: Palette { resolved.palette }

    // resolved derives the palette. An unparsable hex falls back to the default for that slot.
    public var resolved: Resolved {
        let defaults = CustomColors()
        let bg = RGB(hex: background) ?? RGB(hex: defaults.background)!
        let ac = RGB(hex: accent) ?? RGB(hex: defaults.accent)!
        return Palette.derived(
            background: bg, accent: ac, collar: collar.flatMap { RGB(hex: $0) }, late: late.flatMap { RGB(hex: $0) }
        )
    }

    // seeded returns the preset's colors as custom colors, a starting point for editing.
    public static func seeded(from theme: ThemeName) -> CustomColors {
        let p = theme.palette
        return CustomColors(background: p.background.hex, accent: p.accent.hex, collar: p.collar?.hex, late: p.late.hex)
    }
}

extension RGB {
    // hex is the color as lowercase #rrggbb.
    public var hex: String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }

    // mixed returns this color moved toward other by amount, from 0 (this) to 1 (other).
    public func mixed(toward other: RGB, by amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(
            red: red + (other.red - red) * t, green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }
}

extension Palette {
    // readableMinimum is the contrast the background must give its text, so the surface and muted
    // colors derived from it have room.
    static let readableMinimum = 7.0
    // mutedMinimum is the contrast the derived muted color keeps against the background and surface.
    static let mutedMinimum = 5.0
    // accentMinimum is the contrast the ring and buttons keep against the background.
    static let accentMinimum = 3.0
    // step is how far each nudge moves a color toward the pole.
    private static let step = 0.02

    // derived builds a palette from picked colors. Text is black or white, whichever reads better on the
    // background. The background, accent and late colors are honored when they pass and nudged toward the
    // text pole until they do, and every nudge is reported.
    public static func derived(background: RGB, accent: RGB, collar: RGB?, late: RGB?) -> CustomColors.Resolved {
        var adjusted = Set<CustomColors.Slot>()
        var bg = background
        let text: RGB = RGB.white.contrast(with: bg) >= RGB.black.contrast(with: bg) ? .white : .black
        let pole: RGB = text == .white ? .black : .white
        while text.contrast(with: bg) < readableMinimum {
            bg = bg.mixed(toward: pole, by: step)
            adjusted.insert(.background)
        }
        let surface = bg.mixed(toward: text, by: 0.06)
        var muted = text
        var t = 0.0
        while t < 1 {
            let candidate = text.mixed(toward: bg, by: t)
            if candidate.contrast(with: bg) < mutedMinimum || candidate.contrast(with: surface) < mutedMinimum {
                break
            }
            muted = candidate
            t += 0.01
        }
        // An accent that reads as small text on the background must also read on the surface, since
        // accentText then uses it on both.
        var ac = accent
        while ac.contrast(with: bg) < accentMinimum
            || (ac.contrast(with: bg) >= textMinimum && ac.contrast(with: surface) < textMinimum) {
            ac = ac.mixed(toward: text, by: step)
            adjusted.insert(.accent)
        }
        var lt = late ?? (text == .white ? RGB(hex: "#ff7361")! : RGB(hex: "#b3261e")!)
        while lt.contrast(with: bg) < textMinimum || lt.contrast(with: surface) < textMinimum {
            lt = lt.mixed(toward: text, by: step)
            if late != nil {
                adjusted.insert(.late)
            }
        }
        let palette = Palette(
            background: bg, surface: surface, text: text, muted: muted, accent: ac, late: lt, collar: collar
        )
        return CustomColors.Resolved(palette: palette, adjusted: adjusted)
    }
}
