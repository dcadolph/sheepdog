import Foundation
import Testing

@testable import SheepdogCore

// testPaletteContrast checks every theme against WCAG AA for each pairing the alert surfaces use.
@Test(arguments: ThemeName.allCases)
func testPaletteContrast(theme: ThemeName) {
    let p = theme.palette
    let text = Palette.textMinimum
    #expect(p.text.contrast(with: p.background) >= text, "text on background")
    #expect(p.text.contrast(with: p.surface) >= text, "text on surface")
    #expect(p.muted.contrast(with: p.background) >= text, "muted on background")
    #expect(p.muted.contrast(with: p.surface) >= text, "muted on surface")
    #expect(p.accent.contrast(with: p.background) >= 3, "accent on background")
    #expect(p.onAccent.contrast(with: p.accent) >= text, "label on accent")
    #expect(p.accentText.contrast(with: p.background) >= text, "accent text on background")
    #expect(p.accentText.contrast(with: p.surface) >= text, "accent text on surface")
    #expect(p.late.contrast(with: p.background) >= text, "late on background")
    #expect(p.late.contrast(with: p.surface) >= text, "late on surface")
}

// testPaletteFallbacks checks the label and accent text fallbacks, on palettes built to need them and on
// themes that do not.
@Test func testPaletteFallbacks() {
    let dark = RGB(hex: "#0e0c0c")!
    let text = RGB(hex: "#f4f1ee")!
    func palette(_ accent: String) -> Palette {
        Palette(background: dark, surface: dark, text: text, muted: text, accent: RGB(hex: accent)!, late: text)
    }
    #expect(palette("#d6282f").onAccent == .white)
    #expect(palette("#b04cc8").onAccent == .black)
    #expect(palette("#d6282f").accentText == text)
    #expect(ThemeName.wolf.palette.onAccent == ThemeName.wolf.palette.background)
    #expect(ThemeName.rubie.palette.onAccent == ThemeName.rubie.palette.background)
    #expect(ThemeName.wolf.palette.accentText == ThemeName.wolf.palette.accent)
}

// testThemeCollars checks that only Wolf keeps the drawing's collar and that every other collar differs.
@Test func testThemeCollars() {
    #expect(ThemeName.wolf.palette.collar == nil)
    let collars = ThemeName.allCases.filter { $0 != .wolf }.compactMap(\.palette.collar)
    #expect(collars.count == ThemeName.allCases.count - 1)
    for (i, a) in collars.enumerated() {
        for b in collars[(i + 1)...] {
            #expect(a != b)
        }
    }
}

// testContrastKnownValues checks the contrast math against WCAG's black and white extremes.
@Test func testContrastKnownValues() {
    #expect(abs(RGB.black.contrast(with: .white) - 21) < 0.001)
    #expect(RGB.white.contrast(with: .white) == 1)
}

// testRGBHex checks hex parsing.
@Test func testRGBHex() {
    #expect(RGB(hex: "#ff0080") == RGB(red: 1, green: 0, blue: 128.0 / 255))
    #expect(RGB(hex: "00ff00") == RGB(red: 0, green: 1, blue: 0))
    #expect(RGB(hex: "#fff") == nil)
    #expect(RGB(hex: "#gggggg") == nil)
    #expect(RGB(hex: "") == nil)
}

// testThemeSetting checks the default, a round trip, and that an unknown or removed theme keeps the rest.
@Test func testThemeSetting() throws {
    #expect(AlertSettings().theme == .wolf)
    var settings = AlertSettings()
    settings.theme = .blackDiamond
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AlertSettings.self, from: data).theme == .blackDiamond)
    let unknown = #"{"theme":"plaid","maxSnoozes":4}"#
    let got = try JSONDecoder().decode(AlertSettings.self, from: Data(unknown.utf8))
    #expect(got.theme == .wolf)
    #expect(got.maxSnoozes == 4)
    for removed in ["copper", "harbor", "rose"] {
        let json = #"{"theme":"\#(removed)","maxSnoozes":3}"#
        let kept = try JSONDecoder().decode(AlertSettings.self, from: Data(json.utf8))
        #expect(kept.theme == .wolf)
        #expect(kept.maxSnoozes == 3)
    }
}
