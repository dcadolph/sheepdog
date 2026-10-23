import Foundation

// OffHours is what Tug does for a meeting that starts outside working hours.
public enum OffHours: String, Sendable, Codable, CaseIterable, Identifiable {
    case silent
    case quiet
    case full

    // id identifies the option in pickers.
    public var id: String { rawValue }

    // label is the option's user-facing name.
    public var label: String {
        switch self {
        case .silent:
            return "Silent"
        case .quiet:
            return "Quiet: countdown only, no sound"
        case .full:
            return "Full alarm"
        }
    }
}

// WorkingHours limits barking to shifts on chosen weekdays. A shift belongs to the day it starts on, so
// an overnight shift that starts Friday runs into Saturday morning.
public struct WorkingHours: Sendable, Codable, Equatable {
    // Enabled reports whether meetings outside working hours are treated differently.
    public var enabled: Bool = false
    // Start is when a shift begins, in minutes after local midnight.
    public var start: Int = 8 * 60
    // End is when a shift ends, in minutes after local midnight. At or before start, the shift runs overnight.
    public var end: Int = 18 * 60
    // Weekdays are the Calendar weekday numbers a shift can start on, where 1 is Sunday, kept sorted.
    public var weekdays: [Int] = [2, 3, 4, 5, 6]
    // Outside is what Tug does for a meeting that starts outside working hours.
    public var outside: OffHours = .silent

    // minutesPerDay bounds start and end.
    static let minutesPerDay = 24 * 60

    // init creates working hours with the defaults: off, and Mon-Fri 8:00 to 18:00 once turned on.
    public init() {}

    // init decodes working hours, falling back to defaults for any missing or out of range field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WorkingHours()
        let validMinute = 0..<Self.minutesPerDay
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        start = try container.decodeIfPresent(Int.self, forKey: .start).flatMap { validMinute.contains($0) ? $0 : nil }
            ?? defaults.start
        end = try container.decodeIfPresent(Int.self, forKey: .end).flatMap { validMinute.contains($0) ? $0 : nil }
            ?? defaults.end
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays)
            .map { Array(Set($0.filter { (1...7).contains($0) })).sorted() } ?? defaults.weekdays
        // An unknown choice, e.g. one from a newer build, falls back instead of failing every setting.
        outside = (try? container.decodeIfPresent(OffHours.self, forKey: .outside)) ?? defaults.outside
    }

    // contains reports whether date falls inside a shift, read on the local wall clock so DST needs no special case.
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = parts.hour, let minute = parts.minute, let weekday = parts.weekday else {
            return false
        }
        let now = hour * 60 + minute
        if start < end {
            return start <= now && now < end && weekdays.contains(weekday)
        }
        if now >= start {
            return weekdays.contains(weekday)
        }
        if now < end {
            return weekdays.contains(weekday == 1 ? 7 : weekday - 1)
        }
        return false
    }

    // treatment returns what Tug does for a meeting that starts at start: full when hours are off or it is inside.
    public func treatment(for start: Date, calendar: Calendar) -> OffHours {
        guard enabled, outside != .full, !contains(start, calendar: calendar) else {
            return .full
        }
        return outside
    }

    // gate drops the meetings Tug stays silent for and returns the ids of those held to the countdown.
    public func gate(_ meetings: [Meeting], calendar: Calendar) -> (alerting: [Meeting], quiet: Set<String>) {
        var alerting: [Meeting] = []
        var quiet: Set<String> = []
        for meeting in meetings {
            switch treatment(for: meeting.start, calendar: calendar) {
            case .silent:
                continue
            case .quiet:
                quiet.insert(meeting.id)
            case .full:
                break
            }
            alerting.append(meeting)
        }
        return (alerting, quiet)
    }

    // isOffDuty reports whether Tug is holding back for meetings that would start at now.
    public func isOffDuty(now: Date, calendar: Calendar) -> Bool {
        treatment(for: now, calendar: calendar) != .full
    }

    // nextStart returns the first shift start strictly after now, or nil when no weekday is checked.
    public func nextStart(after now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let begins = calendar.date(
                      bySettingHour: start / 60, minute: start % 60, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
                  ),
                  begins > now
            else {
                continue
            }
            return begins
        }
        return nil
    }
}
