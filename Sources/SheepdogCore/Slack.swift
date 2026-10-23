import Foundation

// SlackChannel is a channel the user can message from the alarm.
public struct SlackChannel: Sendable, Codable, Equatable, Identifiable {
    // ID identifies the row in settings.
    public var id = UUID()
    // Name is the label the user typed, e.g. #team.
    public var name: String
    // Link is the channel link as pasted from Slack.
    public var link: String

    // init creates a channel.
    public init(name: String, link: String) {
        self.name = name
        self.link = link
    }

    // channelLink parses the pasted link, or returns nil when it is not a Slack channel link.
    public var channelLink: SlackLink? {
        SlackLink.parse(link)
    }

    // label is the name, or the channel id when no name was typed.
    public var label: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return trimmed
        }
        return channelLink?.channelID ?? "Slack"
    }
}

// SlackLink is a Slack channel link and the URL that opens it in the Slack app.
public struct SlackLink: Sendable, Equatable {
    // ChannelID is the channel's id, e.g. C0123ABCD.
    public var channelID: String
    // Web is the channel's web link.
    public var web: URL
    // Native is the slack:// link when the team is known, or the web link.
    public var native: URL

    // archivesPattern matches Slack's "Copy link" form on any workspace host.
    private static let archivesPattern = #"^https://[\w.-]+\.slack\.com/archives/([CGD][A-Z0-9]{6,})(?:[/?#].*)?$"#
    // clientPattern matches the web client form, which carries the team id.
    private static let clientPattern = #"^https://app\.slack\.com/client/(T[A-Z0-9]{6,})/([CGD][A-Z0-9]{6,})(?:[/?#].*)?$"#

    // parse reads a pasted channel link.
    public static func parse(_ text: String) -> SlackLink? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let groups = match(raw, clientPattern), groups.count == 2,
           let web = URL(string: "https://app.slack.com/client/\(groups[0])/\(groups[1])"),
           let native = URL(string: "slack://channel?team=\(groups[0])&id=\(groups[1])") {
            return SlackLink(channelID: groups[1], web: web, native: native)
        }
        if let groups = match(raw, archivesPattern), groups.count == 1,
           let host = URL(string: raw)?.host,
           let web = URL(string: "https://\(host)/archives/\(groups[0])") {
            return SlackLink(channelID: groups[0], web: web, native: web)
        }
        return nil
    }

    // match returns the capture groups of the first match of pattern in text.
    private static func match(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<result.numberOfRanges).compactMap { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

// TeamMessage is a ready-made line for the user to paste into Slack.
public enum TeamMessage: Sendable, Equatable {
    case runningLate
    case cantMake

    // text fills the message in for a meeting title.
    public func text(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let meeting = trimmed.isEmpty ? "the meeting" : trimmed
        switch self {
        case .runningLate:
            return "Running a few minutes late to \(meeting)."
        case .cantMake:
            return "I can't make \(meeting)."
        }
    }
}
