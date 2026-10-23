import Foundation
import Observation

import SheepdogCore

// SettingsStore persists AlertSettings in user defaults and publishes changes.
@MainActor
@Observable
final class SettingsStore {
    // settings is the live configuration. Every change is saved immediately.
    var settings: AlertSettings {
        didSet { save() }
    }

    // key is the user defaults key holding the encoded settings.
    private static let key = "alertSettings"

    // init loads saved settings, or the defaults when none are saved or they fail to decode.
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(AlertSettings.self, from: data) {
            settings = saved
        } else {
            settings = AlertSettings()
        }
    }

    // reset restores the defaults and keeps the Slack channels and theme, which are setup rather than
    // tuning.
    func reset() {
        var fresh = AlertSettings()
        fresh.slackChannels = settings.slackChannels
        fresh.theme = settings.theme
        settings = fresh
    }

    // save writes the settings to user defaults.
    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
