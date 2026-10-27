import SwiftUI

import SheepdogCore

// WorkingHoursFields edits whether working hours apply and when they run, shared by Settings and the setup window.
struct WorkingHoursFields: View {
    // store holds the live settings.
    @Bindable var store: SettingsStore

    // body lays out the working hours switch above the start, end and days it enables.
    var body: some View {
        Toggle("Only bark during working hours", isOn: $store.settings.workingHours.enabled)
        Group {
            DatePicker("Start", selection: shiftMinutes(\.start), displayedComponents: .hourAndMinute)
            DatePicker("End", selection: shiftMinutes(\.end), displayedComponents: .hourAndMinute)
            LabeledContent("Days") {
                HStack {
                    ForEach(Self.weekdayOrder, id: \.self) { day in
                        Toggle(Calendar.current.veryShortWeekdaySymbols[day - 1], isOn: weekday(day))
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
        .disabled(!store.settings.workingHours.enabled)
    }

    // weekdayOrder lists Calendar weekday numbers starting from the locale's first day of the week.
    private static let weekdayOrder: [Int] = {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }()

    // shiftMinutes binds a time picker to a working hours field held in minutes after midnight.
    private func shiftMinutes(_ field: WritableKeyPath<WorkingHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = store.settings.workingHours[keyPath: field]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())
                    ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.settings.workingHours[keyPath: field] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // weekday binds a checkbox to whether a shift can start on that Calendar weekday.
    private func weekday(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { store.settings.workingHours.weekdays.contains(day) },
            set: { checked in
                var days = Set(store.settings.workingHours.weekdays)
                if checked {
                    days.insert(day)
                } else {
                    days.remove(day)
                }
                store.settings.workingHours.weekdays = days.sorted()
            }
        )
    }
}
