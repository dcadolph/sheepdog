import Foundation

// TugSound is one of Tug's bundled bark recordings, offered beside the macOS alert sounds.
public enum TugSound: String, Sendable, CaseIterable, Identifiable {
    case woof = "Tug Woof"
    case barking = "Tug Barking"

    // id identifies the sound in pickers and is the name stored in settings.
    public var id: String { rawValue }

    // resource is the bundled file name without its extension.
    public var resource: String {
        switch self {
        case .woof:
            return "tug-woof"
        case .barking:
            return "tug-barking"
        }
    }
}
