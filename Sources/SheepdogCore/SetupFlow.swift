import Foundation

// SetupStep is one screen of the first-run setup flow.
public enum SetupStep: Sendable, CaseIterable, Equatable {
    // access asks for calendar access.
    case access
    // connect lists the calendars to watch.
    case connect
    // bark chooses when Tug barks.
    case bark
    // dressUp offers Tug's outfits.
    case dressUp
    // done closes the flow.
    case done

    // title is the heading shown for the step.
    public var title: String {
        switch self {
        case .access: "Welcome"
        case .connect: "Connect calendars"
        case .bark: "When should Tug bark?"
        case .dressUp: "Tug dresses up"
        case .done: "Done"
        }
    }
}

// SetupFlowRecord remembers that the setup flow was completed and by which build.
public struct SetupFlowRecord: Sendable, Codable, Equatable {
    // completed is when the user finished the flow, or nil when it was never finished.
    public var completed: Date?
    // version is the build that completed the flow.
    public var version: String

    // init creates a record.
    public init(completed: Date?, version: String) {
        self.completed = completed
        self.version = version
    }
}

// SetupFlow decides which setup steps to show.
public enum SetupFlow {
    // steps returns the steps to show for a launch. A fresh install has no stored settings.
    public static func steps(fresh: Bool, record: SetupFlowRecord?) -> [SetupStep] {
        if record?.completed != nil {
            return []
        }
        return fresh ? SetupStep.allCases : [.dressUp, .done]
    }

    // reopenSteps returns the steps to show when the user reopens setup from settings.
    public static func reopenSteps(accessGranted: Bool, usesMacCalendar: Bool) -> [SetupStep] {
        if accessGranted || !usesMacCalendar {
            return [.connect, .bark, .dressUp, .done]
        }
        return SetupStep.allCases
    }

    // startsAtLogin returns the Done step's starting login choice. Only a fresh install that has not made
    // the choice yet starts on, so a later reopen shows what the user picked instead of turning it back on.
    public static func startsAtLogin(fresh: Bool, configured: Bool, enabled: Bool, needsApproval: Bool) -> Bool {
        (fresh && !configured) || enabled || needsApproval
    }
}
