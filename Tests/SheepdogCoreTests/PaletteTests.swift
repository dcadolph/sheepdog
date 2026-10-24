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

// testPaletteFallbacks checks the label and accent text fallbacks on the themes that need them.
@Test func testPaletteFallbacks() {
    #expect(ThemeName.rose.palette.onAccent == .white)
    #expect(ThemeName.tyrian.palette.onAccent == .black)
    #expect(ThemeName.harbor.palette.onAccent == ThemeName.harbor.palette.background)
    #expect(ThemeName.rose.palette.accentText == ThemeName.rose.palette.text)
    #expect(ThemeName.harbor.palette.accentText == ThemeName.harbor.palette.accent)
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

// testThemeSetting checks the default, a round trip, and that an unknown theme keeps the rest.
@Test func testThemeSetting() throws {
    #expect(AlertSettings().theme == .harbor)
    var settings = AlertSettings()
    settings.theme = .arrakis
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AlertSettings.self, from: data).theme == .arrakis)
    let unknown = #"{"theme":"plaid","maxSnoozes":4}"#
    let got = try JSONDecoder().decode(AlertSettings.self, from: Data(unknown.utf8))
    #expect(got.theme == .harbor)
    #expect(got.maxSnoozes == 4)
}
