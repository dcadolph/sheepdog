import EventKit
import Foundation

import SheepdogCore

// CalendarProvider reads upcoming events from every calendar macOS knows about.
@MainActor
final class CalendarProvider {
    // Access is the state of calendar permission.
    enum Access {
        case unknown
        case granted
        case denied
    }

    // onChange is called when the calendar store reports a change.
    var onChange: (() -> Void)?
    // access is the current permission state.
    private(set) var access: Access = .unknown
    // store is the EventKit store shared for the app's lifetime.
    private let store = EKEventStore()
    // lookahead is how far ahead events are fetched.
    private let lookahead: TimeInterval = 12 * 3600

    // init subscribes to store change notifications.
    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        access = Self.currentAccess()
    }

    // requestAccess asks for full calendar access and returns whether it was granted. It uses the
    // completion handler form because the async form sends the main actor's store across actors,
    // which the macOS 15 SDK rejects.
    func requestAccess() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        access = granted ? .granted : .denied
        return granted
    }

    // entries returns events from shortly in the past through the lookahead window.
    func entries(now: Date) -> [CalendarEntry] {
        guard access == .granted else {
            return []
        }
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(lookahead),
            calendars: nil
        )
        return store.events(matching: predicate).map(Self.entry)
    }

    // currentAccess maps the system authorization status to Access.
    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .granted
        case .notDetermined:
            return .unknown
        default:
            return .denied
        }
    }

    // entry converts an EventKit event into a CalendarEntry.
    private static func entry(_ event: EKEvent) -> CalendarEntry {
        let attendees = event.attendees ?? []
        let me = attendees.first { $0.isCurrentUser }
        return CalendarEntry(
            eventID: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isFree: event.availability == .free,
            status: status(me?.participantStatus),
            attendeeCount: attendees.filter { !$0.isCurrentUser }.count,
            url: event.url,
            location: event.location,
            notes: event.notes
        )
    }

    // status maps an EventKit participant status to the core type.
    private static func status(_ value: EKParticipantStatus?) -> CalendarEntry.ParticipationStatus {
        switch value {
        case .accepted, .delegated, .completed, .inProcess:
            return .accepted
        case .tentative:
            return .tentative
        case .declined:
            return .declined
        case .pending:
            return .pending
        default:
            return .unknown
        }
    }
}
