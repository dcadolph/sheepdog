import Foundation

// SetupSource is one calendar source the system reports, such as an account in macOS Calendar.
public struct SetupSource: Sendable, Codable, Equatable {
    // Kind is the type of service behind a source.
    public enum Kind: String, Sendable, Codable, Equatable {
        // local is a source stored only on this Mac.
        case local
        // icloud is an iCloud source.
        case icloud
        // exchange is an Exchange or Microsoft source.
        case exchange
        // google is a Google source.
        case google
        // caldav is a generic CalDAV source.
        case caldav
        // other is any source that fits no other kind.
        case other
    }

    // kind is the type of service behind the source.
    public var kind: Kind
    // title is the display name of the source.
    public var title: String
    // calendarCount is the number of calendars the source holds.
    public var calendarCount: Int
    // calendars are the source's calendars, sorted by title.
    public var calendars: [SetupCalendar]

    // init creates a source.
    public init(kind: Kind, title: String, calendarCount: Int, calendars: [SetupCalendar] = []) {
        self.kind = kind
        self.title = title
        self.calendarCount = calendarCount
        self.calendars = calendars
    }
}

// SetupAccess is the state of the macOS Calendar permission.
public enum SetupAccess: String, Sendable, Codable, Equatable {
    // granted means the user allowed calendar access.
    case granted
    // denied means the user refused calendar access.
    case denied
    // unknown means the permission has not been decided or could not be read.
    case unknown
}

// SetupFacts is what the app observed about calendar setup at one moment.
public struct SetupFacts: Sendable, Equatable {
    // macCalendarOn is true when macOS Calendar is a watched source.
    public var macCalendarOn: Bool
    // macCalendarAccess is the state of the macOS Calendar permission.
    public var macCalendarAccess: SetupAccess
    // sources lists the calendar sources macOS reports.
    public var sources: [SetupSource]
    // availableKinds is the set of account kinds the app can connect.
    public var availableKinds: Set<AccountKind>
    // connectedKinds is the set of account kinds already connected.
    public var connectedKinds: Set<AccountKind>
    // installedApps lists the bundle ids of apps installed on this Mac.
    public var installedApps: Set<String>
    // lastMeetingSeen is when a meeting was last seen, or nil if none.
    public var lastMeetingSeen: Date?
    // firstRun is when the app first ran, or nil if unknown.
    public var firstRun: Date?
    // now is the moment the facts describe.
    public var now: Date

    // init creates facts with quiet defaults.
    public init(
        macCalendarOn: Bool = true,
        macCalendarAccess: SetupAccess = .granted,
        sources: [SetupSource] = [],
        availableKinds: Set<AccountKind> = [],
        connectedKinds: Set<AccountKind> = [],
        installedApps: Set<String> = [],
        lastMeetingSeen: Date? = nil,
        firstRun: Date? = nil,
        now: Date
    ) {
        self.macCalendarOn = macCalendarOn
        self.macCalendarAccess = macCalendarAccess
        self.sources = sources
        self.availableKinds = availableKinds
        self.connectedKinds = connectedKinds
        self.installedApps = installedApps
        self.lastMeetingSeen = lastMeetingSeen
        self.firstRun = firstRun
        self.now = now
    }
}

// SetupHint is one piece of advice about a calendar setup problem.
public enum SetupHint: String, Sendable, Codable, Equatable {
    // noAccess means macOS Calendar is on but access is denied.
    case noAccess
    // nothingConnected means no calendar is visible from any source.
    case nothingConnected
    // outlookWithoutMicrosoft means Outlook or Teams is installed but no Microsoft calendar shows.
    case outlookWithoutMicrosoft
    // quietWeek means no meeting was seen for a week.
    case quietWeek

    // ActionKind is the button a hint offers.
    public enum ActionKind: String, Sendable, Codable, Equatable {
        // allowAccess opens the Calendar privacy settings.
        case allowAccess
        // openCalendars opens Settings on the Calendars tab.
        case openCalendars
    }

    // message is the text shown to the user.
    public var message: String {
        switch self {
        case .noAccess:
            return "Tug can't see macOS Calendar."
        case .nothingConnected:
            return "Tug doesn't see any calendar yet."
        case .outlookWithoutMicrosoft:
            return "You have Outlook, but Tug doesn't see a Microsoft calendar."
        case .quietWeek:
            return "Tug hasn't seen a meeting in a week. "
                + "If you have them, he may be watching the wrong calendars."
        }
    }

    // detail is the way around a blocked direct sign-in, for hints about a missing account.
    public var detail: String? {
        switch self {
        case .nothingConnected, .outlookWithoutMicrosoft:
            return "If your company blocks direct sign-in, add the account in System Settings, "
                + "Internet Accounts, and Tug reads it through macOS Calendar."
        case .noAccess, .quietWeek:
            return nil
        }
    }

    // action is the one action the hint offers.
    public var action: ActionKind {
        switch self {
        case .noAccess:
            return .allowAccess
        case .nothingConnected, .outlookWithoutMicrosoft, .quietWeek:
            return .openCalendars
        }
    }
}

// CalendarSetup derives setup hints from observed facts.
public enum CalendarSetup {
    // quietAfter is the age of first run and last meeting that makes a week quiet.
    public static let quietAfter: TimeInterval = 7 * 86400
    // microsoftApps lists the bundle ids of apps that imply a Microsoft calendar.
    public static let microsoftApps: Set<String> = [
        "com.microsoft.Outlook", "com.microsoft.teams2", "com.microsoft.teams",
    ]

    // hints returns the applicable hints in display order.
    public static func hints(_ facts: SetupFacts) -> [SetupHint] {
        var found: [SetupHint] = []
        if facts.macCalendarOn && facts.macCalendarAccess == .denied {
            found.append(.noAccess)
        }
        let seesCalendar = facts.sources.contains { $0.calendarCount > 0 }
        if !seesCalendar && facts.connectedKinds.isEmpty {
            found.append(.nothingConnected)
        }
        let hasMicrosoftApp = !facts.installedApps.isDisjoint(with: microsoftApps)
        let hasExchange = facts.sources.contains { $0.kind == .exchange }
        if hasMicrosoftApp && !hasExchange && facts.availableKinds.contains(.microsoft)
            && !facts.connectedKinds.contains(.microsoft)
        {
            found.append(.outlookWithoutMicrosoft)
        }
        if let firstRun = facts.firstRun, facts.now.timeIntervalSince(firstRun) >= quietAfter {
            if let seen = facts.lastMeetingSeen {
                if facts.now.timeIntervalSince(seen) >= quietAfter {
                    found.append(.quietWeek)
                }
            } else {
                found.append(.quietWeek)
            }
        }
        return found
    }

    // readThroughApple returns the account kinds whose calendars Tug already reads through macOS Calendar, so
    // a direct sign-in to them is optional. An Exchange source covers Microsoft 365 as well as Exchange.
    public static func readThroughApple(_ facts: SetupFacts) -> Set<AccountKind> {
        guard facts.macCalendarOn && facts.macCalendarAccess == .granted else {
            return []
        }
        var kinds: Set<AccountKind> = []
        for source in facts.sources where source.calendarCount > 0 {
            switch source.kind {
            case .icloud:
                kinds.insert(.icloud)
            case .exchange:
                kinds.formUnion([.microsoft, .exchange])
            case .google:
                kinds.insert(.google)
            case .caldav:
                kinds.insert(.caldav)
            case .local, .other:
                break
            }
        }
        return kinds
    }
}

// SetupNudge remembers which hints the user was shown and when to remind them again.
public struct SetupNudge: Sendable, Codable, Equatable {
    // reminderWait is the wait between one showing and the next.
    public static let reminderWait: TimeInterval = 3 * 86400
    // maxReminders is the number of reminders after which the nudge goes quiet.
    public static let maxReminders = 3

    // hints is the hint set the nudge last saw.
    public var hints: [SetupHint] = []
    // lastShown is when the user was last shown the hint set.
    public var lastShown: Date?
    // reminders counts the reminders shown after the first showing.
    public var reminders: Int = 0
    // silenced is true when the user stopped the card for good.
    public var silenced: Bool = false

    // init creates an empty nudge.
    public init() {}

    // see records the current hint set, and restarts the schedule when it changes to a new one.
    public mutating func see(hints: [SetupHint]) {
        guard hints != self.hints else {
            return
        }
        self.hints = hints
        if !hints.isEmpty {
            lastShown = nil
            reminders = 0
        }
    }

    // due reports whether the user should be shown the hints now.
    public func due(now: Date, blocked: Bool) -> Bool {
        guard !blocked, !silenced, !hints.isEmpty else {
            return false
        }
        guard let lastShown else {
            return true
        }
        guard reminders < Self.maxReminders else {
            return false
        }
        return now.timeIntervalSince(lastShown) >= Self.reminderWait || now < lastShown
    }

    // shown records that the user was shown the hints.
    public mutating func shown(now: Date) {
        if lastShown != nil {
            reminders += 1
        }
        lastShown = now
    }

    // silence stops the card for good.
    public mutating func silence() {
        silenced = true
    }
}
