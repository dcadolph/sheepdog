import Foundation

// JoinLink is a meeting link and the URL that opens it in the native app.
public struct JoinLink: Sendable, Equatable {
    // Provider is the video service a link belongs to.
    public enum Provider: String, Sendable, Equatable {
        case teams = "Teams"
        case zoom = "Zoom"
        case meet = "Google Meet"
        case webex = "Webex"
        case slack = "Slack"
        case other = "Link"
    }

    // Provider is the service the link belongs to.
    public var provider: Provider
    // Web is the link as found in the event.
    public var web: URL
    // Native is the URL that opens the link in the provider's app, or the web link when none exists.
    public var native: URL

    // init creates a link.
    public init(provider: Provider, web: URL, native: URL) {
        self.provider = provider
        self.web = web
        self.native = native
    }

    // webexBundleID is the bundle identifier of the Webex app.
    public static let webexBundleID = "Cisco-Systems.Spark"
    // slackBundleID is the bundle identifier of the Slack app.
    public static let slackBundleID = "com.tinyspeck.slackmacgap"

    // route returns how to open the link for the chosen target.
    public func route(_ choice: JoinOpen) -> JoinRoute {
        switch provider {
        case .teams:
            if choice == .browser || native == web {
                return .open(web, fallback: nil)
            }
            return .open(native, fallback: web)
        case .zoom:
            if choice == .browser {
                return .open(zoomWebClient, fallback: nil)
            }
            if native == web {
                return .open(web, fallback: nil)
            }
            return .open(native, fallback: web)
        case .webex:
            if choice == .browser {
                return .open(web, fallback: nil)
            }
            return .handTo(bundleID: Self.webexBundleID, url: web, fallback: web)
        case .slack:
            if choice == .browser {
                return .open(web, fallback: nil)
            }
            return .handTo(bundleID: Self.slackBundleID, url: web, fallback: web)
        case .meet, .other:
            return .open(web, fallback: nil)
        }
    }

    // zoomWebClient is the Zoom web client URL for the link, keeping only the pwd query item.
    private var zoomWebClient: URL {
        let parts = web.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "j",
            var components = URLComponents(url: web, resolvingAgainstBaseURL: false)
        else {
            return web
        }
        components.path = "/wc/join/\(parts[1])"
        let pwd = components.queryItems?.first(where: { $0.name == "pwd" })
        components.queryItems = pwd.map { [$0] }
        return components.url ?? web
    }
}

// JoinOpen is where a meeting link opens.
public enum JoinOpen: String, Sendable, Codable, CaseIterable {
    case app
    case browser

    // label is the name shown in settings.
    public var label: String {
        switch self {
        case .app: return "In the app"
        case .browser: return "In the browser"
        }
    }
}

// JoinOpens holds the open choice for each provider that has a Mac app.
public struct JoinOpens: Sendable, Codable, Equatable {
    // Teams is where Teams links open.
    public var teams: JoinOpen = .app
    // Zoom is where Zoom links open.
    public var zoom: JoinOpen = .app
    // Webex is where Webex links open.
    public var webex: JoinOpen = .app
    // Slack is where Slack huddle links open.
    public var slack: JoinOpen = .app

    // init creates the defaults, which open everything in the app.
    public init() {}

    // init decodes each field on its own so a missing or unknown value falls back to its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = JoinOpens()
        teams = (try? container.decodeIfPresent(JoinOpen.self, forKey: .teams)) ?? defaults.teams
        zoom = (try? container.decodeIfPresent(JoinOpen.self, forKey: .zoom)) ?? defaults.zoom
        webex = (try? container.decodeIfPresent(JoinOpen.self, forKey: .webex)) ?? defaults.webex
        slack = (try? container.decodeIfPresent(JoinOpen.self, forKey: .slack)) ?? defaults.slack
    }

    // choice returns the open choice for a provider. Meet and other links always use the browser.
    public func choice(for provider: JoinLink.Provider) -> JoinOpen {
        switch provider {
        case .teams: return teams
        case .zoom: return zoom
        case .webex: return webex
        case .slack: return slack
        case .meet, .other: return .browser
        }
    }
}

// JoinRoute is how a meeting link is opened.
public enum JoinRoute: Sendable, Equatable {
    // open opens the URL and tries the fallback if that fails.
    case open(URL, fallback: URL?)
    // handTo opens the URL inside the app with the bundle ID, or opens the fallback in the browser.
    case handTo(bundleID: String, url: URL, fallback: URL)
}

// JoinLinkFinder extracts meeting links from event fields.
public enum JoinLinkFinder {
    // patterns lists recognized meeting URLs, most specific first.
    private static let patterns: [(JoinLink.Provider, String)] = [
        (.teams, #"https://teams\.microsoft\.com/l/meetup-join/[^\s"<>]+"#),
        (.teams, #"https://teams\.microsoft\.com/meet/[^\s"<>]+"#),
        (.teams, #"https://teams\.live\.com/meet/[^\s"<>]+"#),
        (.zoom, #"https://[\w.-]*zoom\.us/j/\d+[^\s"<>]*"#),
        (.meet, #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\s"<>]*"#),
        (.webex, #"https://[\w.-]*webex\.com/[^\s"<>]+"#),
        (.slack, #"https://app\.slack\.com/huddle/[A-Z0-9]+/[A-Z0-9]+[^\s"<>]*"#),
    ]

    // find returns the first meeting link in the entry's URL, location, then notes.
    public static func find(in entry: CalendarEntry) -> JoinLink? {
        let fields = [entry.url?.absoluteString, entry.location, entry.notes].compactMap { $0 }
        for field in fields {
            if let link = find(in: field) {
                return link
            }
        }
        if let url = entry.url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            return JoinLink(provider: .other, web: url, native: url)
        }
        return nil
    }

    // find returns the first recognized meeting link in text.
    public static func find(in text: String) -> JoinLink? {
        var best: (range: Range<String.Index>, provider: JoinLink.Provider)?
        for (provider, pattern) in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else {
                continue
            }
            if best == nil || range.lowerBound < best!.range.lowerBound {
                best = (range, provider)
            }
        }
        guard let best else {
            return nil
        }
        let raw = String(text[best.range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)>]"))
        guard let web = URL(string: raw) else {
            return nil
        }
        return JoinLink(provider: best.provider, web: web, native: nativeURL(for: web, provider: best.provider))
    }

    // nativeURL converts a web meeting link into the provider's app URL scheme where one exists.
    static func nativeURL(for web: URL, provider: JoinLink.Provider) -> URL {
        switch provider {
        case .teams:
            let raw = web.absoluteString
            guard let host = web.host, let range = raw.range(of: "https://\(host)") else {
                return web
            }
            return URL(string: raw.replacingCharacters(in: range, with: "msteams:")) ?? web
        case .zoom:
            let parts = web.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "j" else {
                return web
            }
            var query = "confno=\(parts[1])"
            if let pwd = URLComponents(url: web, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pwd" })?.value {
                query += "&pwd=\(pwd)"
            }
            return URL(string: "zoommtg://\(web.host ?? "zoom.us")/join?action=join&\(query)") ?? web
        case .meet, .webex, .slack, .other:
            return web
        }
    }
}
