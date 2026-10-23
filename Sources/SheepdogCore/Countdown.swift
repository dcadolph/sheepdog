import Foundation

// Countdown formats the time between now and a meeting start for display.
public enum Countdown {
    // clock formats a duration as m:ss, or h:mm:ss at an hour or more. Negative durations use their magnitude.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(abs(seconds).rounded(.up))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // phrase describes the start relative to now, e.g. "Starts in 4:32" or "Started 1:05 ago".
    public static func phrase(start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if delta > 0 {
            return "Starts in \(clock(delta))"
        }
        if delta > -1 {
            return "Starting now"
        }
        return "Started \(clock(delta)) ago"
    }

    // short gives a compact menu bar label, e.g. "4m", "45s", or "now".
    public static func short(start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if delta <= 0 {
            return "now"
        }
        if delta < 60 {
            return "\(Int(delta.rounded(.up)))s"
        }
        return "\(Int((delta / 60).rounded(.up)))m"
    }

    // relative describes the start in words, e.g. "in 2h 10m", "in 4 min", "now" or "5 min ago". Future minutes
    // round up and past minutes round down.
    public static func relative(start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if delta > 0 && delta < 60 {
            return "in under a minute"
        }
        if delta > -60 && delta <= 0 {
            return "now"
        }
        let minutes = delta > 0 ? Int((delta / 60).rounded(.up)) : Int((-delta / 60).rounded(.down))
        let span: String
        if minutes < 60 {
            span = "\(minutes) min"
        } else if minutes % 60 == 0 {
            span = "\(minutes / 60)h"
        } else {
            span = "\(minutes / 60)h \(minutes % 60)m"
        }
        return delta > 0 ? "in \(span)" : "\(span) ago"
    }

    // remaining returns the share of span left before start, from 1 at span or more out to 0 at the start.
    public static func remaining(start: Date, now: Date, span: TimeInterval) -> Double {
        guard span > 0 else {
            return 0
        }
        return min(1, max(0, start.timeIntervalSince(now) / span))
    }
}
