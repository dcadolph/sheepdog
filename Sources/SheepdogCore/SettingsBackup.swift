import Foundation

// SettingsBackup is the file a user exports to keep their settings and imports to restore them.
// Sign-ins are never part of it, since they live in the Keychain.
public struct SettingsBackup: Sendable, Codable, Equatable {
    // App names the app that wrote the file.
    public var app: String
    // Version is the file format version.
    public var version: Int
    // Exported is when the file was written.
    public var exported: Date
    // Settings is the saved configuration.
    public var settings: AlertSettings

    // appName is the app value this build writes and accepts.
    public static let appName = "Sheepdog"
    // currentVersion is the newest format this build reads, and the one it writes.
    public static let currentVersion = 1
    // fileName is the suggested name for an exported file.
    public static let fileName = "Sheepdog Settings.json"

    // encode writes settings as pretty JSON with sorted keys, so the file diffs cleanly.
    public static func encode(_ settings: AlertSettings, exported: Date) throws -> Data {
        let backup = SettingsBackup(app: appName, version: currentVersion, exported: exported, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // decode reads a backup file and returns its settings, refusing other apps and newer formats.
    public static func decode(_ data: Data) throws -> AlertSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw BackupError.unreadable
        }
        guard header.app == appName else {
            throw BackupError.notSheepdog(header.app)
        }
        guard header.version <= currentVersion else {
            throw BackupError.newerVersion(header.version)
        }
        guard let backup = try? decoder.decode(SettingsBackup.self, from: data) else {
            throw BackupError.unreadable
        }
        return backup.settings
    }

    // Header is the part of the file read before trusting the rest.
    private struct Header: Decodable {
        // App names the app that wrote the file.
        let app: String
        // Version is the file format version.
        let version: Int
    }
}
