import Foundation

// Support holds the treat link baked into the app bundle at build time and the project's code home.
enum Support {
    // treatTip is the hover text on the Buy Tug a treat menu item.
    static let treatTip =
        "Tug doesn't need kibble, but keeping him barking takes work. A treat helps keep him well trained."
    // contributeTip is the hover text on the Contribute on GitHub link.
    static let contributeTip = "Code, bug reports and ideas are welcome on GitHub."
    // repo is the project's GitHub page.
    static let repo = URL(string: "https://github.com/dcadolph/sheepdog")!
    // url is the https treat link, or nil when the build has none.
    static let url: URL? = {
        guard let text = (Bundle.main.object(forInfoDictionaryKey: "SheepdogSupportURL") as? String)?
            .trimmingCharacters(in: .whitespaces),
            let url = URL(string: text), url.scheme == "https", url.host != nil
        else {
            return nil
        }
        return url
    }()
}
