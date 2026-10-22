import Foundation

import SheepdogCore

// HeldPlaceStore persists held notes in user defaults so a restart mid-meeting keeps them.
@MainActor
final class HeldPlaceStore {
    // places are the held and handed back notes. Every change is saved immediately.
    var places: [HeldPlace] {
        didSet {
            if places != oldValue {
                save()
            }
        }
    }

    // key is the user defaults key holding the encoded notes.
    private static let key = "heldPlaces"

    // init loads saved notes, or none when nothing is saved or it fails to decode.
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([HeldPlace].self, from: data) {
            places = saved
        } else {
            places = []
        }
    }

    // save writes the notes to user defaults.
    private func save() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
