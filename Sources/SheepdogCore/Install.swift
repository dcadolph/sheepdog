import Foundation

// MountedImage is one attached disk image and where its volume is mounted.
public struct MountedImage: Sendable, Equatable {
    // image is the path of the disk image file.
    public let image: String
    // mount is the path the image's volume is mounted at.
    public let mount: String

    // init records an image and its mount point.
    public init(image: String, mount: String) {
        self.image = image
        self.mount = mount
    }
}

// InstallPlace is where a running copy of Sheepdog lives, which decides what the first launch offers.
public enum InstallPlace: Sendable, Equatable {
    // applications is an Applications folder, or anywhere a build was put by hand, so nothing is offered.
    case applications
    // diskImage is the volume of a mounted disk image, so the copy is offered to Applications.
    case diskImage(MountedImage)
    // elsewhere is a downloaded copy outside an Applications folder, so a move is offered.
    case elsewhere
}

// Install decides where Sheepdog runs from and which disk images hold it.
public enum Install {
    // appName is the bundle's file name.
    public static let appName = "Sheepdog.app"

    // place classifies a bundle path. A copy on a mounted image is offered the copy whether or not
    // it is quarantined. A copy outside an Applications folder is offered the move only when it is
    // quarantined, so builds made on this Mac (make run, .build) are never asked.
    public static func place(bundle: String, quarantined: Bool, images: [MountedImage], home: String) -> InstallPlace {
        let path = trimmed(bundle)
        if let image = images.first(where: { inside(path, folder: $0.mount) }) {
            return .diskImage(image)
        }
        if inApplications(bundle: path, home: home) || !quarantined {
            return .applications
        }
        return .elsewhere
    }

    // inApplications reports whether a bundle path is in /Applications or the home Applications folder.
    public static func inApplications(bundle: String, home: String) -> Bool {
        let path = trimmed(bundle)
        return ["/Applications", trimmed(home) + "/Applications"].contains { inside(path, folder: $0) }
    }

    // images reads the attached disk images from `hdiutil info -plist` output. An image without a
    // mounted volume is left out.
    public static func images(hdiutilPlist data: Data) -> [MountedImage] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let list = root["images"] as? [[String: Any]]
        else { return [] }
        return list.compactMap { entry in
            guard let image = entry["image-path"] as? String,
                  let entities = entry["system-entities"] as? [[String: Any]],
                  let mount = entities.compactMap({ $0["mount-point"] as? String }).first
            else { return nil }
            return MountedImage(image: image, mount: mount)
        }
    }

    // holding returns the mounted disk images whose volume has Sheepdog.app at its top, the
    // installer an installed copy should offer to eject and trash.
    public static func holding(_ images: [MountedImage], exists: (String) -> Bool) -> [MountedImage] {
        images.filter { $0.image.hasSuffix(".dmg") && exists(trimmed($0.mount) + "/" + appName) }
    }

    // homebrew reports whether Homebrew manages Sheepdog, by the presence of its Caskroom folder
    // on Apple silicon or Intel.
    public static func homebrew(exists: (String) -> Bool) -> Bool {
        ["/opt/homebrew/Caskroom/sheepdog", "/usr/local/Caskroom/sheepdog"].contains { exists($0) }
    }

    // brewPath returns the Homebrew executable, Apple silicon first, or nil when neither exists.
    public static func brewPath(exists: (String) -> Bool) -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { exists($0) }
    }

    // brewScript returns the shell script that upgrades the cask, quits Sheepdog, waits for it to
    // exit, and opens the new copy. A failed upgrade leaves Sheepdog running. It quits with a signal,
    // since an Apple event from Terminal would first ask the user to let Terminal control Sheepdog.
    public static func brewScript(brew: String, app: String) -> String {
        [
            "#!/bin/sh",
            "if ! \(shellQuoted(brew)) upgrade --cask sheepdog; then",
            "  echo",
            "  echo 'Sheepdog was not updated.'",
            "  exit 1",
            "fi",
            "/usr/bin/pkill -x Sheepdog",
            "waited=0",
            "while /usr/bin/pgrep -x Sheepdog >/dev/null && [ \"$waited\" -lt 75 ]; do",
            "  sleep 0.2",
            "  waited=$((waited + 1))",
            "done",
            "/usr/bin/open \(shellQuoted(app))",
            "echo 'Sheepdog is up to date. You can close this window.'",
            "",
        ].joined(separator: "\n")
    }

    // dmgURL is the release disk image download for a tag, used exactly as given.
    public static func dmgURL(tag: String) -> URL {
        URL(string: "https://github.com/dcadolph/sheepdog/releases/download/\(tag)/"
            + "sheepdog_\(tag)_macos_universal.dmg")!
    }

    // shellQuoted wraps a value in single quotes, escaping any single quote inside it.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // inside reports whether path is folder or below it.
    static func inside(_ path: String, folder: String) -> Bool {
        let base = trimmed(folder)
        return !base.isEmpty && (path == base || path.hasPrefix(base + "/"))
    }

    // trimmed drops a trailing slash so paths compare the same either way.
    static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    // imageKey identifies one disk image file by path, file number, and creation time in whole
    // seconds, so a file replaced at the same path gets a different key.
    public static func imageKey(path: String, fileNumber: UInt64, created: Date) -> String {
        "\(path)|\(fileNumber)|\(Int64(created.timeIntervalSince1970))"
    }

    // pruned keeps the keys whose file still has that identity. The path of a key is everything
    // before its last two separators, so a path containing a separator still round-trips.
    public static func pruned(_ keys: [String], current: (String) -> String?) -> [String] {
        keys.filter { key in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return false }
            let path = parts.dropLast(2).joined(separator: "|")
            return current(path) == key
        }
    }
}
