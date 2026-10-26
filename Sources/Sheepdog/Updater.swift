import AppKit
import os

import SheepdogCore

// Updater installs a newer release when the user presses Update now on the update card. A Homebrew
// install upgrades through brew in the background. A disk image install downloads the release's image,
// checks who signed the app on it, and starts that copy, which installs itself.
@MainActor
final class Updater {
    // scriptName is the file name of the script a Homebrew upgrade runs.
    static let scriptName = "sheepdog-update.sh"
    // logName is the file name of the log a Homebrew upgrade writes its output to.
    static let logName = "sheepdog-update.log"

    // logger writes to the unified log under the com.dcadolph.sheepdog subsystem.
    private let logger = Logger(subsystem: "com.dcadolph.sheepdog", category: "update")

    // canUpdate reports whether this copy may update itself, which only an installed copy in
    // /Applications may do, so a build run from anywhere else never replaces it.
    static var canUpdate: Bool {
        Installer.originalURL(Bundle.main.bundleURL).standardizedFileURL.path == Installer.destination.path
    }

    // brew runs the upgrade script in the background with its output in the update log. It runs the
    // script directly rather than through Terminal, which types a .command file into the user's login
    // shell, where shell startup can mangle it. On success the script quits and reopens Sheepdog, so
    // this returns only when the upgrade could not start or failed.
    func brew() async throws {
        guard let brew = Install.brewPath(exists: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UpdaterError.noBrew
        }
        let folder = try Self.folder()
        let script = folder.appendingPathComponent(Self.scriptName)
        let log = folder.appendingPathComponent(Self.logName)
        let text = Install.brewScript(brew: brew, app: Installer.destination.path)
        try Data(text.utf8).write(to: script, options: .atomic)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier)]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = output
        task.standardError = output
        logger.notice("started the Homebrew upgrade for the update")
        let status: Int32 = try await withCheckedThrowingContinuation { done in
            task.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do {
                try task.run()
            } catch {
                done.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw UpdaterError.brew(status: status)
        }
    }

    // install downloads the disk image of the release named by tag, mounts it, checks that the app on
    // it is a signed Sheepdog of that version, and starts it to install itself. On any failure it
    // detaches and deletes what it made.
    func install(tag: String) async throws {
        let image = try Self.folder().appendingPathComponent(Install.dmgURL(tag: tag).lastPathComponent)
        try await download(Install.dmgURL(tag: tag), to: image)
        var mount: String?
        do {
            let volume = try await Task.detached { try Self.attach(image) }.value
            mount = volume
            let app = URL(fileURLWithPath: volume).appendingPathComponent(Install.appName)
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            try await Task.detached { try Self.check(app, version: version) }.value
            try await launch(app, image: image)
            logger.notice("started the update from \(image.path, privacy: .public)")
        } catch {
            if let mount {
                Installer.run("/usr/bin/hdiutil", "detach", mount, "-force")
            }
            try? FileManager.default.removeItem(at: image)
            throw error
        }
    }

    // download fetches url into file, replacing any earlier copy.
    private func download(_ url: URL, to file: URL) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (temp, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw UpdaterError.download(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        try FileManager.default.moveItem(at: temp, to: file)
    }

    // attach mounts the disk image without showing it in the Finder and returns its volume. It runs off
    // the main thread because hdiutil verifies the image first.
    private nonisolated static func attach(_ image: URL) throws -> String {
        let task = Process()
        let out = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", "-nobrowse", "-noautoopen", "-plist", image.path]
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw UpdaterError.attach }
        return mount
    }

    // launch starts the copy on the image as a second instance, handing it the image to install from.
    private func launch(_ app: URL, image: URL) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = [Installer.updateFromFlag, image.path]
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: config)
    }

    // check verifies that app meets the release signing requirement and carries version.
    nonisolated static func check(_ app: URL, version: String) throws {
        guard Install.signed(app.path, requirement: Install.releaseRequirement) else {
            throw UpdaterError.signature
        }
        let found = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard found == version else {
            throw UpdaterError.version
        }
    }

    // folder returns the app's caches folder, where downloads and the upgrade script are kept.
    private static func folder() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil,
                                                 create: true)
        let folder = caches.appendingPathComponent(bundleID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // bundleID is Sheepdog's bundle identifier.
    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.dcadolph.sheepdog"
    }
}
