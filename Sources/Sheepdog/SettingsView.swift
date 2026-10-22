import SwiftUI

import SheepdogCore

// SettingsView edits every AlertSettings field.
struct SettingsView: View {
    // store holds the live settings.
    @Bindable var store: SettingsStore
    // onTestAlarm runs a full takeover with a fake meeting.
    let onTestAlarm: () -> Void
    // leadsText is the editable warning leads, in minutes, separated by commas.
    @State private var leadsText = ""

    // sounds lists the built-in alert sounds for the pickers.
    private let sounds = SoundPlayer.availableSounds()

    // body lays out the settings form.
    var body: some View {
        Form {
            Section("Warnings") {
                TextField("Warn at (minutes before, comma separated)", text: $leadsText)
                    .onSubmit(applyLeads)
                    .onChange(of: leadsText) { applyLeads() }
                Toggle("Show the floating countdown", isOn: $store.settings.showPill)
                Picker("Warning chime", selection: $store.settings.chimeSound) {
                    ForEach(sounds, id: \.self) { Text($0) }
                }
            }
            Section("Takeover") {
                Stepper(
                    "Full-screen alarm \(Int(store.settings.takeoverLead)) sec before start",
                    value: $store.settings.takeoverLead,
                    in: 0...600,
                    step: 15
                )
                Stepper(
                    "Keep at you for \(Int(store.settings.nagWindow / 60)) min after start",
                    value: $store.settings.nagWindow,
                    in: 60...3600,
                    step: 60
                )
                Picker("Alarm sound", selection: $store.settings.alarmSound) {
                    ForEach(sounds, id: \.self) { Text($0) }
                }
            }
            Section("Snooze") {
                Stepper("Snoozes per meeting: \(store.settings.maxSnoozes)", value: $store.settings.maxSnoozes, in: 0...10)
                Stepper(
                    "Before start: \(Int(store.settings.snoozeBeforeStart)) sec",
                    value: $store.settings.snoozeBeforeStart,
                    in: 15...300,
                    step: 15
                )
                Stepper(
                    "After start: \(Int(store.settings.snoozeAfterStart)) sec",
                    value: $store.settings.snoozeAfterStart,
                    in: 15...300,
                    step: 15
                )
            }
            Section("Sound output") {
                Picker("Play alerts on", selection: $store.settings.alarmOutput) {
                    ForEach(AlarmOutput.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Unmute and raise volume during the alarm", isOn: $store.settings.boostVolume)
                if store.settings.boostVolume {
                    Slider(value: $store.settings.boostLevel, in: 0.2...1) {
                        Text("At least \(Int(store.settings.boostLevel * 100))%")
                    }
                }
            }
            Section("Which events alert") {
                Toggle("Include tentative meetings", isOn: $store.settings.includeTentative)
                Toggle("Skip events with no other attendees", isOn: $store.settings.requireAttendees)
            }
            Section {
                HStack {
                    Button("Test the alarm", action: onTestAlarm)
                    Spacer()
                    Button("Restore defaults") {
                        store.reset()
                        leadsText = Self.format(store.settings.warningLeads)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear { leadsText = Self.format(store.settings.warningLeads) }
    }

    // applyLeads parses the leads text and saves it when every value is a valid minute count.
    private func applyLeads() {
        let parts = leadsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let minutes = parts.compactMap(Double.init)
        guard minutes.count == parts.count, minutes.allSatisfy({ $0 > 0 && $0 <= 120 }) else {
            return
        }
        store.settings.warningLeads = minutes.map { $0 * 60 }.sorted(by: >)
    }

    // format renders leads in seconds as a comma separated minute list.
    private static func format(_ leads: [TimeInterval]) -> String {
        leads.map { lead in
            let minutes = lead / 60
            return minutes == minutes.rounded() ? String(Int(minutes)) : String(minutes)
        }.joined(separator: ", ")
    }
}
