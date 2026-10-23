import Foundation

// NapLength is how long Tug sleeps when the user puts him down for a nap.
public enum NapLength: String, Sendable, CaseIterable {
    case oneHour
    case threeHours
    case untilMorning
    case untilWoken
}

// Nap decides when a nap ends and whether Tug is still asleep.
public enum Nap {
    // morningHour is the local hour when a nap until morning ends.
    public static let morningHour = 6
    // forever marks a nap that lasts until the user wakes Tug.
    public static let forever = Date.distantFuture

    // until returns when a nap of the given length that starts at now ends. With working hours on, a nap until
    // morning ends when the next shift starts.
    public static func until(
        _ length: NapLength, now: Date, calendar: Calendar, hours: WorkingHours = WorkingHours()
    ) -> Date {
        switch length {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .threeHours:
            return now.addingTimeInterval(3 * 3600)
        case .untilMorning:
            return workStart(after: now, calendar: calendar, hours: hours)
                ?? nextMorning(after: now, calendar: calendar)
        case .untilWoken:
            return forever
        }
    }

    // isNapping reports whether a nap that ends at until is still going at now.
    public static func isNapping(until: Date?, now: Date) -> Bool {
        guard let until else {
            return false
        }
        return now < until
    }

    // morningLabel names the until-morning choice, which ends this morning between midnight and the morning hour,
    // or when work starts with working hours on.
    public static func morningLabel(now: Date, calendar: Calendar, hours: WorkingHours = WorkingHours()) -> String {
        if workStart(after: now, calendar: calendar, hours: hours) != nil {
            return "Until work starts"
        }
        return calendar.isDate(nextMorning(after: now, calendar: calendar), inSameDayAs: now)
            ? "Until this morning"
            : "Until tomorrow morning"
    }

    // workStart returns the next shift start when working hours are on and a weekday is checked.
    static func workStart(after now: Date, calendar: Calendar, hours: WorkingHours) -> Date? {
        hours.enabled ? hours.nextStart(after: now, calendar: calendar) : nil
    }

    // nextMorning returns the first morning hour strictly after now.
    static func nextMorning(after now: Date, calendar: Calendar) -> Date {
        let mark = DateComponents(hour: morningHour, minute: 0, second: 0)
        return calendar.nextDate(after: now, matching: mark, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86400)
    }
}
