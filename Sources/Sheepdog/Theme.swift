import SwiftUI

import SheepdogCore

// Theme holds the colors of the current theme for every alert surface.
@MainActor
enum Theme {
    // palette is the current theme's colors. The coordinator sets it whenever settings change.
    static var palette = ThemeName.harbor.palette

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
