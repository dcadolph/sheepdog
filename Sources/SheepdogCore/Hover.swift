import Foundation

// Hover writes the text shown when the pointer rests on the menu bar icon.
public enum Hover {
    // titleLimit is the longest meeting title shown before it is cut short.
    static let titleLimit = 48

    // status says what Tug is doing: the meeting he is alerting for, else the nap and the next meeting.
    public static func status(active: Meeting?, next: Meeting?, napLine: String?, now: Date) -> String {
        if let active {
            let delta = active.start.timeIntervalSince(now)
            let verb = delta > -60 && delta <= 0 ? "is starting" : delta > 0 ? "starts" : "started"
            return "\(title(active)) \(verb) \(Countdown.relative(start: active.start, now: now))"
        }
        var lines: [String] = []
        if let napLine {
            lines.append(napLine)
        }
        if let next {
            lines.append("Next: \(title(next)) \(Countdown.relative(start: next.start, now: now))")
        }
        if lines.isEmpty {
            return "No meetings in the next 12 hours"
        }
        return lines.joined(separator: "\n")
    }

    // title returns a meeting's title, cut short with an ellipsis when it is long.
    static func title(_ meeting: Meeting) -> String {
        meeting.title.count > titleLimit ? meeting.title.prefix(titleLimit - 1) + "…" : meeting.title
    }
}
