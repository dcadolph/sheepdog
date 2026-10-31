import Foundation

// AlarmOutput chooses which speakers the alarm and chimes play through.
public enum AlarmOutput: String, Sendable, Codable, CaseIterable, Identifiable {
    case systemDefault
    case builtInSpeakers
    case both

    // id identifies the option in pickers.
    public var id: String { rawValue }

    // label is the option's user-facing name.
    public var label: String {
        switch self {
        case .systemDefault:
            return "Current output (headphones if connected)"
        case .builtInSpeakers:
            return "Built-in speakers"
        case .both:
            return "Current output and built-in speakers"
        }
    }
}

// AlertSettings holds every user-tunable timing and filter.
public struct AlertSettings: Sendable, Codable, Equatable {
    // WarningLeads are the seconds before start at which a chime plays and the countdown pill shows.
    public var warningLeads: [TimeInterval] = [600, 300]
    // TakeoverLead is the seconds before start at which the full-screen alarm takes over.
    public var takeoverLead: TimeInterval = 60
    // NagWindow is the seconds after start during which an unresolved meeting keeps alerting.
    public var nagWindow: TimeInterval = 600
    // SnoozeBeforeStart is how long a snooze lasts while the meeting has not started.
    public var snoozeBeforeStart: TimeInterval = 60
    // SnoozeAfterStart is how long a snooze lasts once the meeting has started.
    public var snoozeAfterStart: TimeInterval = 30
    // MaxSnoozes is how many snoozes a single meeting allows.
    public var maxSnoozes: Int = 2
    // IncludeTentative reports whether tentatively accepted meetings alert.
    public var includeTentative: Bool = false
    // RequireAttendees reports whether events with no other attendees are skipped.
    public var requireAttendees: Bool = false
    // AlarmSound is the name of the Tug or system sound that loops during a takeover.
    public var alarmSound: String = TugSound.barking.rawValue
    // ChimeSound is the name of the Tug or system sound that plays at each warning.
    public var chimeSound: String = TugSound.woof.rawValue
    // AlarmOutput is where the alarm and chimes play.
    public var alarmOutput: AlarmOutput = .both
    // BoostVolume reports whether the alarm unmutes and raises output volume while it plays.
    public var boostVolume: Bool = true
    // BoostLevel is the minimum output volume, from 0 to 1, while the alarm plays.
    public var boostLevel: Double = 0.6
    // ShowPill reports whether the floating countdown appears during warnings.
    public var showPill: Bool = true
    // HoldPlace reports whether the warning asks what the user was in the middle of.
    public var holdPlace: Bool = true
    // UseMacCalendar reports whether events come from the calendars in macOS Calendar.
    public var useMacCalendar: Bool = true
    // HiddenCalendarIDs are the Apple Calendar calendars the user unchecked. Empty means every calendar.
    public var hiddenCalendarIDs: Set<String> = []
    // SlackChannels are the channels the alarm's Let them know button can open.
    public var slackChannels: [SlackChannel] = []
    // Theme colors the takeover, the pill, and the hand-back card.
    public var theme: ThemeName = .jax
    // CustomColors are the picked colors the custom theme derives its palette from.
    public var customColors = CustomColors()
    // ShowOutfits reports whether Tug dresses up for holidays.
    public var showOutfits: Bool = false
    // HolidayTunes reports whether Tug's barks play as a holiday tune while an outfit is worn.
    public var holidayTunes: Bool = false
    // JoinOpens chooses whether each provider's links open in its app or the browser.
    public var joinOpens: JoinOpens = JoinOpens()
    // CheckForUpdates reports whether Sheepdog asks GitHub every six hours for a newer release.
    public var checkForUpdates: Bool = true
    // InstallUpdates reports whether Sheepdog installs a newer release itself at a quiet moment.
    public var installUpdates: Bool = true
    // WorkingHours limits barking to shifts on chosen weekdays.
    public var workingHours = WorkingHours()

    // init creates settings with the defaults.
    public init() {}

    // init decodes settings, falling back to defaults for any missing field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AlertSettings()
        warningLeads = try container.decodeIfPresent([TimeInterval].self, forKey: .warningLeads) ?? defaults.warningLeads
        takeoverLead = try container.decodeIfPresent(TimeInterval.self, forKey: .takeoverLead) ?? defaults.takeoverLead
        nagWindow = try container.decodeIfPresent(TimeInterval.self, forKey: .nagWindow) ?? defaults.nagWindow
        snoozeBeforeStart = try container.decodeIfPresent(TimeInterval.self, forKey: .snoozeBeforeStart)
            ?? defaults.snoozeBeforeStart
        snoozeAfterStart = try container.decodeIfPresent(TimeInterval.self, forKey: .snoozeAfterStart)
            ?? defaults.snoozeAfterStart
        maxSnoozes = try container.decodeIfPresent(Int.self, forKey: .maxSnoozes) ?? defaults.maxSnoozes
        includeTentative = try container.decodeIfPresent(Bool.self, forKey: .includeTentative) ?? defaults.includeTentative
        requireAttendees = try container.decodeIfPresent(Bool.self, forKey: .requireAttendees) ?? defaults.requireAttendees
        alarmSound = try container.decodeIfPresent(String.self, forKey: .alarmSound) ?? defaults.alarmSound
        chimeSound = try container.decodeIfPresent(String.self, forKey: .chimeSound) ?? defaults.chimeSound
        alarmOutput = try container.decodeIfPresent(AlarmOutput.self, forKey: .alarmOutput) ?? defaults.alarmOutput
        boostVolume = try container.decodeIfPresent(Bool.self, forKey: .boostVolume) ?? defaults.boostVolume
        boostLevel = try container.decodeIfPresent(Double.self, forKey: .boostLevel) ?? defaults.boostLevel
        showPill = try container.decodeIfPresent(Bool.self, forKey: .showPill) ?? defaults.showPill
        holdPlace = try container.decodeIfPresent(Bool.self, forKey: .holdPlace) ?? defaults.holdPlace
        useMacCalendar = try container.decodeIfPresent(Bool.self, forKey: .useMacCalendar) ?? defaults.useMacCalendar
        hiddenCalendarIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenCalendarIDs)
            ?? defaults.hiddenCalendarIDs
        slackChannels = try container.decodeIfPresent([SlackChannel].self, forKey: .slackChannels)
            ?? defaults.slackChannels
        // An unknown theme, e.g. one from a newer build, falls back instead of failing every setting.
        theme = (try? container.decodeIfPresent(ThemeName.self, forKey: .theme)) ?? defaults.theme
        customColors = (try? container.decodeIfPresent(CustomColors.self, forKey: .customColors))
            ?? defaults.customColors
        showOutfits = try container.decodeIfPresent(Bool.self, forKey: .showOutfits) ?? defaults.showOutfits
        holidayTunes = try container.decodeIfPresent(Bool.self, forKey: .holidayTunes) ?? defaults.holidayTunes
        joinOpens = try container.decodeIfPresent(JoinOpens.self, forKey: .joinOpens) ?? defaults.joinOpens
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates)
            ?? defaults.checkForUpdates
        installUpdates = try container.decodeIfPresent(Bool.self, forKey: .installUpdates)
            ?? defaults.installUpdates
        workingHours = try container.decodeIfPresent(WorkingHours.self, forKey: .workingHours)
            ?? defaults.workingHours
    }

    // palette is the colors of the chosen theme, the derived custom palette when the theme is custom.
    public var palette: Palette {
        theme == .custom ? customColors.palette : theme.palette
    }

    // validSlackChannels are the channels whose links parse.
    public var validSlackChannels: [SlackChannel] {
        slackChannels.filter { $0.channelLink != nil }
    }

    // earliestLead is the largest lead time, when the first alert for a meeting can appear.
    public var earliestLead: TimeInterval {
        max(warningLeads.max() ?? 0, takeoverLead)
    }
}
