import Foundation
import Testing

@testable import SheepdogCore

// testPaletteContrast checks every preset against WCAG AA for each pairing the alert surfaces use.
@Test(arguments: ThemeName.presets)
func testPaletteContrast(theme: ThemeName) {
    expectReadable(theme.palette)
}

// expectReadable checks one palette against WCAG AA for each pairing the alert surfaces use.
func expectReadable(_ p: Palette, _ comment: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    let text = Palette.textMinimum
    #expect(p.text.contrast(with: p.background) >= text, "text on background \(comment)", sourceLocation: sourceLocation)
    #expect(p.text.contrast(with: p.surface) >= text, "text on surface \(comment)", sourceLocation: sourceLocation)
    #expect(p.muted.contrast(with: p.background) >= text, "muted on background \(comment)", sourceLocation: sourceLocation)
    #expect(p.muted.contrast(with: p.surface) >= text, "muted on surface \(comment)", sourceLocation: sourceLocation)
    #expect(p.accent.contrast(with: p.background) >= 3, "accent on background \(comment)", sourceLocation: sourceLocation)
    #expect(p.onAccent.contrast(with: p.accent) >= text, "label on accent \(comment)", sourceLocation: sourceLocation)
    #expect(p.accentText.contrast(with: p.background) >= text, "accent text on background \(comment)", sourceLocation: sourceLocation)
    #expect(p.accentText.contrast(with: p.surface) >= text, "accent text on surface \(comment)", sourceLocation: sourceLocation)
    #expect(p.late.contrast(with: p.background) >= text, "late on background \(comment)", sourceLocation: sourceLocation)
    #expect(p.late.contrast(with: p.surface) >= text, "late on surface \(comment)", sourceLocation: sourceLocation)
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
    #expect(ThemeName.jax.palette.onAccent == ThemeName.jax.palette.background)
    #expect(ThemeName.rubie.palette.onAccent == ThemeName.rubie.palette.background)
    #expect(ThemeName.jax.palette.accentText == ThemeName.jax.palette.accent)
}

// testThemeCollars checks that only Jax keeps the drawing's collar and that every other collar differs.
@Test func testThemeCollars() {
    #expect(ThemeName.presets.count == 18)
    #expect(ThemeName.allCases.count == 19)
    #expect(ThemeName.jax.palette.collar == nil)
    let collars = ThemeName.presets.filter { $0 != .jax }.compactMap(\.palette.collar)
    #expect(collars.count == ThemeName.presets.count - 1)
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
    #expect(AlertSettings().theme == .jax)
    var settings = AlertSettings()
    settings.theme = .blackDiamond
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AlertSettings.self, from: data).theme == .blackDiamond)
    let unknown = #"{"theme":"plaid","maxSnoozes":4}"#
    let got = try JSONDecoder().decode(AlertSettings.self, from: Data(unknown.utf8))
    #expect(got.theme == .jax)
    #expect(got.maxSnoozes == 4)
    for removed in ["copper", "harbor", "wolf", "grapes"] {
        let json = #"{"theme":"\#(removed)","maxSnoozes":3}"#
        let kept = try JSONDecoder().decode(AlertSettings.self, from: Data(json.utf8))
        #expect(kept.theme == .jax)
        #expect(kept.maxSnoozes == 3)
    }
}

// testDerivedGrid checks that every derived palette over a cube of backgrounds and accents, with and
// without a picked late color, passes the same pairings the presets do.
@Test func testDerivedGrid() {
    let steps = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
    var cube: [RGB] = []
    for r in steps { for g in steps { for b in steps { cube.append(RGB(red: r, green: g, blue: b)) } } }
    let lates: [RGB?] = [nil] + [0.0, 0.5, 1.0].flatMap { r in
        [0.0, 0.5, 1.0].flatMap { g in [0.0, 0.5, 1.0].map { b in RGB(red: r, green: g, blue: b) } }
    }
    for bg in cube {
        for ac in cube {
            expectReadable(Palette.derived(background: bg, accent: ac, collar: nil, late: nil).palette,
                           "bg \(bg.hex) accent \(ac.hex)")
        }
        for late in lates {
            expectReadable(Palette.derived(background: bg, accent: bg, collar: nil, late: late).palette,
                           "bg \(bg.hex) late \(late?.hex ?? "nil")")
        }
    }
}

// testDerivedHonorsGoodPicks checks that picks which already pass come through unchanged and nothing is
// reported adjusted, and that a failing accent is moved and reported.
@Test func testDerivedHonorsGoodPicks() {
    let bg = RGB(hex: "#0f1012")!
    let good = Palette.derived(background: bg, accent: RGB(hex: "#f3e3b8")!, collar: nil, late: RGB(hex: "#ff7361")!)
    #expect(good.adjusted.isEmpty)
    #expect(good.palette.background == bg)
    #expect(good.palette.accent == RGB(hex: "#f3e3b8")!)
    #expect(good.palette.late == RGB(hex: "#ff7361")!)
    #expect(good.palette.text == .white)
    let bad = Palette.derived(background: bg, accent: RGB(hex: "#111111")!, collar: nil, late: nil)
    #expect(bad.adjusted == [.accent])
    #expect(bad.palette.accent != RGB(hex: "#111111")!)
    #expect(bad.palette.accent.contrast(with: bg) >= 3)
    let gray = Palette.derived(background: RGB(hex: "#777777")!, accent: RGB(hex: "#ffffff")!, collar: nil, late: nil)
    #expect(gray.adjusted.contains(.background))
    expectReadable(gray.palette)
}

// testCustomColors checks the defaults, the hex round trip, the bad-hex fallback and seeding from a preset,
// which carries the picked colors through unchanged while the rest is derived.
@Test func testCustomColors() {
    #expect(CustomColors().palette.background == ThemeName.jax.palette.background)
    #expect(CustomColors().palette.accent == ThemeName.jax.palette.accent)
    #expect(CustomColors().palette.collar == nil)
    #expect(ThemeName.custom.palette == CustomColors().palette)
    expectReadable(ThemeName.custom.palette)
    #expect(RGB(hex: "#ff0080")!.hex == "#ff0080")
    let bad = CustomColors(background: "nope", accent: "#4f8bff", collar: "#zzzzzz", late: nil)
    #expect(bad.palette.background == RGB(hex: "#0f1012")!)
    #expect(bad.palette.accent == RGB(hex: "#4f8bff")!)
    #expect(bad.palette.collar == nil)
    let seeded = CustomColors.seeded(from: .lightning)
    #expect(seeded.resolved.adjusted.isEmpty)
    #expect(seeded.palette.background == ThemeName.lightning.palette.background)
    #expect(seeded.palette.accent == ThemeName.lightning.palette.accent)
    #expect(seeded.palette.late == ThemeName.lightning.palette.late)
    #expect(seeded.palette.collar == ThemeName.lightning.palette.collar)
    #expect(seeded.collar == "#ffd400")
    #expect(CustomColors.seeded(from: .jax).collar == nil)
    for theme in ThemeName.presets {
        #expect(CustomColors.seeded(from: theme).resolved.adjusted.isEmpty, "\(theme)")
    }
}

// testCustomSetting checks that settings carry custom colors, that an old backup without them decodes to the
// defaults, and that a bad hex inside them keeps every other setting.
@Test func testCustomSetting() throws {
    var settings = AlertSettings()
    settings.theme = .custom
    settings.customColors = CustomColors(background: "#16081f", accent: "#c77dff", collar: "#7b2cbf", late: nil)
    let data = try JSONEncoder().encode(settings)
    let back = try JSONDecoder().decode(AlertSettings.self, from: data)
    #expect(back.customColors == settings.customColors)
    #expect(back.palette == settings.customColors.palette)
    let old = #"{"theme":"rubie","maxSnoozes":5}"#
    let decoded = try JSONDecoder().decode(AlertSettings.self, from: Data(old.utf8))
    #expect(decoded.customColors == CustomColors())
    #expect(decoded.palette == ThemeName.rubie.palette)
    let bad = ##"{"theme":"custom","customColors":{"background":"bad","accent":"#ff8c1a"},"maxSnoozes":6}"##
    let kept = try JSONDecoder().decode(AlertSettings.self, from: Data(bad.utf8))
    #expect(kept.maxSnoozes == 6)
    #expect(kept.theme == .custom)
    #expect(kept.palette.background == RGB(hex: "#0f1012")!)
    #expect(kept.palette.accent == RGB(hex: "#ff8c1a")!)
}
