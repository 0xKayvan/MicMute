import Foundation

/// User settings persisted in UserDefaults.
public final class Preferences {
    private enum Key {
        static let playSounds = "playSounds"
        static let toggleShortcut = "toggleShortcut"
        static let pttShortcut = "pttShortcut"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var playSounds: Bool {
        get { defaults.object(forKey: Key.playSounds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.playSounds) }
    }

    public var toggleShortcut: Shortcut {
        get { shortcut(Key.toggleShortcut) ?? .defaultToggle }
        set { store(newValue, Key.toggleShortcut) }
    }

    public var pttShortcut: Shortcut {
        get { shortcut(Key.pttShortcut) ?? .defaultPushToTalk }
        set { store(newValue, Key.pttShortcut) }
    }

    private func shortcut(_ key: String) -> Shortcut? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    private func store(_ shortcut: Shortcut, _ key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }
}
