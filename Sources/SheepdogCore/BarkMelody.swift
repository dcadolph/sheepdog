import Foundation

// BarkMelody is a holiday tune that replaces Tug's bark while the matching outfit is worn.
public enum BarkMelody: String, Sendable, CaseIterable {
    case auldLangSyne
    case sweetheart
    case irishWasherwoman
    case mountainKing
    case overTheRiver
    case jingleBells

    // outfit is the outfit whose holiday the tune belongs to.
    public var outfit: Outfit {
        switch self {
        case .auldLangSyne: return .newYears
        case .sweetheart: return .valentines
        case .irishWasherwoman: return .stPatricks
        case .mountainKing: return .halloween
        case .overTheRiver: return .thanksgiving
        case .jingleBells: return .christmas
        }
    }

    // title is the tune's name, shown on the Settings line.
    public var title: String {
        switch self {
        case .auldLangSyne: return "Auld Lang Syne"
        case .sweetheart: return "Let Me Call You Sweetheart"
        case .irishWasherwoman: return "The Irish Washerwoman"
        case .mountainKing: return "In the Hall of the Mountain King"
        case .overTheRiver: return "Over the River and Through the Wood"
        case .jingleBells: return "Jingle Bells"
        }
    }

    // resource is the bundled file name without its extension.
    public var resource: String { "melody-\(outfit.asset)" }

    // current returns the tune to play, or nil when no outfit is active, the tunes are off, or the
    // alarm sound is not one of Tug's barks.
    public static func current(outfit: Outfit?, settings: AlertSettings) -> BarkMelody? {
        guard let outfit, settings.holidayTunes,
              TugSound(rawValue: settings.alarmSound) != nil
        else {
            return nil
        }
        return allCases.first { $0.outfit == outfit }
    }
}
