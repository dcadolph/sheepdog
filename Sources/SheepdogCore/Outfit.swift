import Foundation

// Outfit is a seasonal costume Tug wears on holidays. The raw value is the asset name.
public enum Outfit: String, Sendable, CaseIterable {
    case newYears = "party"
    case valentines = "heart"
    case stPatricks = "shamrock"
    case easter = "easter"
    case halloween = "halloween"
    case thanksgiving = "thanksgiving"
    case christmas = "santa"

    // Window is the rule that picks the local calendar days an outfit is worn each year.
    public enum Window: Sendable, Equatable {
        // fixed spans the same month and day range every year, inclusive at both ends. A window whose
        // start falls after its end wraps across the year end.
        case fixed(startMonth: Int, startDay: Int, endMonth: Int, endDay: Int)
        // weekdayOrdinal is one day: the ordinal occurrence of a weekday in a month, with weekday 1 as
        // Sunday, e.g. the fourth Thursday of November.
        case weekdayOrdinal(month: Int, weekday: Int, ordinal: Int)
        // easterOffset spans days counted from Western Easter Sunday, inclusive at both ends, e.g. -1
        // through 0 for Saturday and Sunday.
        case easterOffset(from: Int, through: Int)

        // contains reports whether the date's local calendar day falls inside the window.
        func contains(_ date: Date, calendar: Calendar) -> Bool {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else {
                return false
            }
            switch self {
            case let .fixed(startMonth, startDay, endMonth, endDay):
                let value = month * 100 + day
                let start = startMonth * 100 + startDay
                let end = endMonth * 100 + endDay
                if start <= end {
                    return value >= start && value <= end
                }
                return value >= start || value <= end
            case let .weekdayOrdinal(wantMonth, weekday, ordinal):
                let rule = DateComponents(
                    year: year, month: wantMonth, weekday: weekday, weekdayOrdinal: ordinal
                )
                guard let target = calendar.date(from: rule) else { return false }
                return calendar.isDate(target, inSameDayAs: date)
            case let .easterOffset(from, through):
                let sunday = Outfit.easterSunday(year: year)
                let easter = DateComponents(year: year, month: sunday.month, day: sunday.day)
                guard let target = calendar.date(from: easter),
                      let offset = calendar.dateComponents(
                          [.day], from: calendar.startOfDay(for: target), to: calendar.startOfDay(for: date)
                      ).day
                else { return false }
                return offset >= from && offset <= through
            }
        }
    }

    // label is the outfit's user-facing name.
    public var label: String {
        switch self {
        case .newYears:
            return "New Year's"
        case .valentines:
            return "Valentine's Day"
        case .stPatricks:
            return "St. Patrick's Day"
        case .easter:
            return "Easter"
        case .halloween:
            return "Halloween"
        case .thanksgiving:
            return "Thanksgiving"
        case .christmas:
            return "Christmas"
        }
    }

    // asset is the name of the image asset for the outfit.
    public var asset: String { rawValue }

    // window is the span of days the outfit is worn.
    public var window: Window {
        switch self {
        case .newYears:
            return .fixed(startMonth: 12, startDay: 31, endMonth: 1, endDay: 1)
        case .valentines:
            return .fixed(startMonth: 2, startDay: 14, endMonth: 2, endDay: 14)
        case .stPatricks:
            return .fixed(startMonth: 3, startDay: 17, endMonth: 3, endDay: 17)
        case .easter:
            return .easterOffset(from: -1, through: 0)
        case .halloween:
            return .fixed(startMonth: 10, startDay: 24, endMonth: 10, endDay: 31)
        case .thanksgiving:
            return .weekdayOrdinal(month: 11, weekday: 5, ordinal: 4)
        case .christmas:
            return .fixed(startMonth: 12, startDay: 18, endMonth: 12, endDay: 26)
        }
    }

    // current returns the outfit active on the date's local calendar day, or nil when none is.
    public static func current(on date: Date, calendar: Calendar) -> Outfit? {
        first(in: allCases.map { ($0, $0.window) }, on: date, calendar: calendar)
    }

    // first returns the earliest entry whose window contains the date's local day.
    static func first(in entries: [(Outfit, Window)], on date: Date, calendar: Calendar) -> Outfit? {
        entries.first { $0.1.contains(date, calendar: calendar) }?.0
    }

    // easterSunday returns the month and day of Western Easter in a Gregorian year, by the Anonymous
    // Gregorian computus.
    static func easterSunday(year: Int) -> (month: Int, day: Int) {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }
}
