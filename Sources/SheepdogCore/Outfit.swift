import Foundation

// Outfit is a seasonal costume Tug wears on fixed dates. The raw value is the asset name.
public enum Outfit: String, Sendable, CaseIterable {
    case newYears = "party"
    case valentines = "heart"
    case stPatricks = "shamrock"
    case halloween = "halloween"
    case christmas = "santa"

    // Window is a span of local calendar days, inclusive at both ends, that repeats every year.
    public struct Window: Sendable, Equatable {
        // StartMonth is the month of the first day, from 1 to 12.
        public let startMonth: Int
        // StartDay is the day of the month of the first day.
        public let startDay: Int
        // EndMonth is the month of the last day, from 1 to 12.
        public let endMonth: Int
        // EndDay is the day of the month of the last day.
        public let endDay: Int

        // contains reports whether the month and day fall inside the window. A window whose start
        // falls after its end wraps across the year end.
        func contains(month: Int, day: Int) -> Bool {
            let value = month * 100 + day
            let start = startMonth * 100 + startDay
            let end = endMonth * 100 + endDay
            if start <= end {
                return value >= start && value <= end
            }
            return value >= start || value <= end
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
        case .halloween:
            return "Halloween"
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
            return Window(startMonth: 12, startDay: 31, endMonth: 1, endDay: 1)
        case .valentines:
            return Window(startMonth: 2, startDay: 14, endMonth: 2, endDay: 14)
        case .stPatricks:
            return Window(startMonth: 3, startDay: 17, endMonth: 3, endDay: 17)
        case .halloween:
            return Window(startMonth: 10, startDay: 24, endMonth: 10, endDay: 31)
        case .christmas:
            return Window(startMonth: 12, startDay: 18, endMonth: 12, endDay: 26)
        }
    }

    // current returns the outfit active on the date's local calendar day, or nil when none is.
    public static func current(on date: Date, calendar: Calendar) -> Outfit? {
        first(in: allCases.map { ($0, $0.window) }, on: date, calendar: calendar)
    }

    // first returns the earliest entry whose window contains the date's local day.
    static func first(in entries: [(Outfit, Window)], on date: Date, calendar: Calendar) -> Outfit? {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        return entries.first { $0.1.contains(month: month, day: day) }?.0
    }
}
