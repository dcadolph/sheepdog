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
    // which the macOS 15 SDK rejects. The completion is @Sendable because EventKit calls it on a
    // background queue, and a closure inferred as main actor traps there on first launch.
    func requestAccess() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { @Sendable granted, _ in
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

    // sources lists the accounts macOS Calendar has, each with its count of event calendars. It reads
    // nothing before access is granted, so it never triggers a prompt.
    func sources() -> [SetupSource] {
        guard access == .granted else {
            return []
        }
        var counts: [String: Int] = [:]
        var byID: [String: EKSource] = [:]
        for calendar in store.calendars(for: .event) {
            guard let source = calendar.source else {
                continue
            }
            counts[source.sourceIdentifier, default: 0] += 1
            byID[source.sourceIdentifier] = source
        }
        return byID.compactMap { id, source in
            Self.kind(source).map {
                SetupSource(kind: $0, title: source.title, calendarCount: counts[id] ?? 0)
            }
        }
        .sorted { (Self.order($0.kind), $0.title) < (Self.order($1.kind), $1.title) }
    }

    // order ranks source kinds for display, accounts with meetings first and this Mac last.
    private static func order(_ kind: SetupSource.Kind) -> Int {
        [.exchange, .google, .icloud, .caldav, .other, .local].firstIndex(of: kind) ?? 0
    }

    // kind maps an EventKit source to a setup kind, or nil for the birthdays source, which holds no
    // meetings.
    private static func kind(_ source: EKSource) -> SetupSource.Kind? {
        switch source.sourceType {
        case .local:
            return .local
        case .mobileMe:
            return .icloud
        case .exchange:
            return .exchange
        case .calDAV:
            let title = source.title.lowercased()
            if title == "icloud" {
                return .icloud
            }
            return title.contains("google") || title.contains("gmail") ? .google : .caldav
        case .birthdays:
            return nil
        default:
            return .other
        }
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
            notes: event.notes,
            webURL: event.eventIdentifier.flatMap(showURL)
        )
    }

    // showURL builds the link that makes Calendar.app open an event.
    private static func showURL(_ eventIdentifier: String) -> URL? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let id = eventIdentifier.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "ical://ekevent/\(id)?method=show&options=more")
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
