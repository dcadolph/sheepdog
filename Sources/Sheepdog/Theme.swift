import SwiftUI

import SheepdogCore

// Theme holds the colors of the current theme for every alert surface.
@MainActor
enum Theme {
    // palette is the current theme's colors. The coordinator sets it whenever settings change.
    static var palette = ThemeName.harbor.palette
    // outfit is the costume Tug wears today, or nil for none. The coordinator sets it every tick.
    static var outfit: Outfit?
    // outfitOverrideKey names a debug default that forces an outfit by asset name, for checking the art.
    static let outfitOverrideKey = "outfitOverride"

    // dressed returns the outfit Tug wears under the settings on the date, honoring the debug override.
    static func dressed(_ settings: AlertSettings, on date: Date = Date()) -> Outfit? {
        guard settings.showOutfits else {
            return nil
        }
        if let name = UserDefaults.standard.string(forKey: outfitOverrideKey) {
            return Outfit(rawValue: name)
        }
        return Outfit.current(on: date, calendar: .current)
    }

    // background is behind the takeover.
    static var background: Color { Color(palette.background) }
    // surface is behind the pill and the hand-back card.
    static var surface: Color { Color(palette.surface) }
    // text is the main text color.
    static var text: Color { Color(palette.text) }
    // muted is the color for hints and secondary lines.
    static var muted: Color { Color(palette.muted) }
    // accent fills the main button and draws the ring.
    static var accent: Color { Color(palette.accent) }
    // onAccent is the label color on an accent fill.
    static var onAccent: Color { Color(palette.onAccent) }
    // accentText is the accent when it is readable as small text, else the text color.
    static var accentText: Color { Color(palette.accentText) }
    // late marks a meeting that has already started.
    static var late: Color { Color(palette.late) }
}

extension Color {
    // init converts a core RGB color.
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
