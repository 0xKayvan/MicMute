import Foundation

/// User settings persisted in UserDefaults.
public final class Preferences {
    private enum Key {
        static let playSounds = "playSounds"
        static let toggleShortcut = "toggleShortcut"
        static let pttShortcut = "pttShortcut"
        static let muteRecord = "muteRecord"
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

    /// What MicMute last changed on the devices (see `MuteRecord`); nil before the first mute.
    public var muteRecord: MuteRecord? {
        get { defaults.data(forKey: Key.muteRecord).flatMap { try? JSONDecoder().decode(MuteRecord.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.muteRecord) }
    }

    private func shortcut(_ key: String) -> Shortcut? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    private func store(_ shortcut: Shortcut, _ key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }
}
