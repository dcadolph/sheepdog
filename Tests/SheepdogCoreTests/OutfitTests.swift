import Foundation
import Testing

@testable import SheepdogCore

// outfitDate returns local noon in Chicago on the given day.
func outfitDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    chicago.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

// OutfitCase is one day checked against the outfit rule.
struct OutfitCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Date is the local day under test.
    let date: Date
    // Want is the outfit expected on that day, or nil for none.
    let want: Outfit?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// outfitCases covers each window's edges, the year wrap, and days in no window.
let outfitCases: [OutfitCase] = [
    OutfitCase(name: "new years first day", date: outfitDate(2026, 12, 31), want: .newYears),
    OutfitCase(name: "new years last day", date: outfitDate(2027, 1, 1), want: .newYears),
    OutfitCase(name: "new years day before", date: outfitDate(2026, 12, 30), want: nil),
    OutfitCase(name: "new years day after", date: outfitDate(2027, 1, 2), want: nil),
    OutfitCase(name: "valentines day", date: outfitDate(2027, 2, 14), want: .valentines),
    OutfitCase(name: "valentines day before", date: outfitDate(2027, 2, 13), want: nil),
    OutfitCase(name: "valentines day after", date: outfitDate(2027, 2, 15), want: nil),
    OutfitCase(name: "st patricks day", date: outfitDate(2027, 3, 17), want: .stPatricks),
    OutfitCase(name: "st patricks day before", date: outfitDate(2027, 3, 16), want: nil),
    OutfitCase(name: "st patricks day after", date: outfitDate(2027, 3, 18), want: nil),
    OutfitCase(name: "easter 2024 friday", date: outfitDate(2024, 3, 29), want: nil),
    OutfitCase(name: "easter 2024 saturday", date: outfitDate(2024, 3, 30), want: .easter),
    OutfitCase(name: "easter 2024 sunday", date: outfitDate(2024, 3, 31), want: .easter),
    OutfitCase(name: "easter 2024 monday", date: outfitDate(2024, 4, 1), want: nil),
    OutfitCase(name: "easter 2025 friday", date: outfitDate(2025, 4, 18), want: nil),
    OutfitCase(name: "easter 2025 saturday", date: outfitDate(2025, 4, 19), want: .easter),
    OutfitCase(name: "easter 2025 sunday", date: outfitDate(2025, 4, 20), want: .easter),
    OutfitCase(name: "easter 2025 monday", date: outfitDate(2025, 4, 21), want: nil),
    OutfitCase(name: "easter 2026 friday", date: outfitDate(2026, 4, 3), want: nil),
    OutfitCase(name: "easter 2026 saturday", date: outfitDate(2026, 4, 4), want: .easter),
    OutfitCase(name: "easter 2026 sunday", date: outfitDate(2026, 4, 5), want: .easter),
    OutfitCase(name: "easter 2026 monday", date: outfitDate(2026, 4, 6), want: nil),
    OutfitCase(name: "easter 2027 friday", date: outfitDate(2027, 3, 26), want: nil),
    OutfitCase(name: "easter 2027 saturday", date: outfitDate(2027, 3, 27), want: .easter),
    OutfitCase(name: "easter 2027 sunday", date: outfitDate(2027, 3, 28), want: .easter),
    OutfitCase(name: "easter 2027 monday", date: outfitDate(2027, 3, 29), want: nil),
    OutfitCase(name: "halloween first day", date: outfitDate(2026, 10, 24), want: .halloween),
    OutfitCase(name: "halloween last day", date: outfitDate(2026, 10, 31), want: .halloween),
    OutfitCase(name: "halloween day before", date: outfitDate(2026, 10, 23), want: nil),
    OutfitCase(name: "halloween day after", date: outfitDate(2026, 11, 1), want: nil),
    OutfitCase(name: "thanksgiving 2025 day before", date: outfitDate(2025, 11, 26), want: nil),
    OutfitCase(name: "thanksgiving 2025", date: outfitDate(2025, 11, 27), want: .thanksgiving),
    OutfitCase(name: "thanksgiving 2025 day after", date: outfitDate(2025, 11, 28), want: nil),
    OutfitCase(name: "thanksgiving 2026 day before", date: outfitDate(2026, 11, 25), want: nil),
    OutfitCase(name: "thanksgiving 2026", date: outfitDate(2026, 11, 26), want: .thanksgiving),
    OutfitCase(name: "thanksgiving 2026 day after", date: outfitDate(2026, 11, 27), want: nil),
    OutfitCase(name: "thanksgiving 2027 day before", date: outfitDate(2027, 11, 24), want: nil),
    OutfitCase(name: "thanksgiving 2027", date: outfitDate(2027, 11, 25), want: .thanksgiving),
    OutfitCase(name: "thanksgiving 2027 day after", date: outfitDate(2027, 11, 26), want: nil),
    OutfitCase(name: "christmas first day", date: outfitDate(2026, 12, 18), want: .christmas),
    OutfitCase(name: "christmas last day", date: outfitDate(2026, 12, 26), want: .christmas),
    OutfitCase(name: "christmas day before", date: outfitDate(2026, 12, 17), want: nil),
    OutfitCase(name: "christmas day after", date: outfitDate(2026, 12, 27), want: nil),
    OutfitCase(name: "midsummer", date: outfitDate(2026, 7, 4), want: nil),
]

// currentMatchesWindows checks Outfit.current against each case.
@Test(arguments: outfitCases)
func currentMatchesWindows(_ test: OutfitCase) {
    #expect(Outfit.current(on: test.date, calendar: chicago) == test.want)
}

// firstUsesDeclarationOrder checks that the earlier entry wins when two windows contain the date.
@Test func firstUsesDeclarationOrder() {
    let date = outfitDate(2026, 12, 31)
    let wide = Outfit.Window.fixed(startMonth: 12, startDay: 1, endMonth: 12, endDay: 31)
    let wrap = Outfit.newYears.window
    #expect(Outfit.first(in: [(.christmas, wide), (.newYears, wrap)], on: date, calendar: chicago) == .christmas)
    #expect(Outfit.first(in: [(.newYears, wrap), (.christmas, wide)], on: date, calendar: chicago) == .newYears)
}

// assetsMatchRawValues checks the asset names the owner chose.
@Test func assetsMatchRawValues() {
    #expect(Outfit.allCases.map(\.asset) == ["party", "heart", "shamrock", "easter", "halloween", "thanksgiving", "santa"])
}

// easterSundayMatchesKnownYears checks the computus against published Easter dates.
@Test func easterSundayMatchesKnownYears() {
    #expect(Outfit.easterSunday(year: 2019) == (4, 21))
    #expect(Outfit.easterSunday(year: 2022) == (4, 17))
    #expect(Outfit.easterSunday(year: 2024) == (3, 31))
    #expect(Outfit.easterSunday(year: 2025) == (4, 20))
    #expect(Outfit.easterSunday(year: 2026) == (4, 5))
    #expect(Outfit.easterSunday(year: 2027) == (3, 28))
}

// movableFeastsIgnoreFirstWeekdayAndZone checks that a Monday-first calendar in another zone picks the
// same local days.
@Test func movableFeastsIgnoreFirstWeekdayAndZone() {
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    tokyo.firstWeekday = 2
    // day returns local noon in Tokyo on the given day.
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    #expect(Outfit.current(on: day(2026, 11, 25), calendar: tokyo) == nil)
    #expect(Outfit.current(on: day(2026, 11, 26), calendar: tokyo) == .thanksgiving)
    #expect(Outfit.current(on: day(2026, 11, 27), calendar: tokyo) == nil)
    #expect(Outfit.current(on: day(2026, 4, 3), calendar: tokyo) == nil)
    #expect(Outfit.current(on: day(2026, 4, 4), calendar: tokyo) == .easter)
    #expect(Outfit.current(on: day(2026, 4, 5), calendar: tokyo) == .easter)
    #expect(Outfit.current(on: day(2026, 4, 6), calendar: tokyo) == nil)
}
