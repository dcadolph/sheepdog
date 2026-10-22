import Foundation

// JoinLink is a meeting link and the URL that opens it in the native app.
public struct JoinLink: Sendable, Equatable {
    // Provider is the video service a link belongs to.
    public enum Provider: String, Sendable, Equatable {
        case teams = "Teams"
        case zoom = "Zoom"
        case meet = "Google Meet"
        case webex = "Webex"
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
        case .meet, .webex, .other:
            return web
        }
    }
}
