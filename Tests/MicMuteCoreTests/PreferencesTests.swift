import Carbon.HIToolbox
import Foundation
import Testing
import MicMuteCore

@Suite struct PreferencesTests {
    func freshDefaults() -> UserDefaults {
        let suite = "micmute-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func hasSensibleDefaults() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.playSounds)
        #expect(prefs.toggleShortcut == .defaultToggle)
        #expect(prefs.pttShortcut == .defaultPushToTalk)
    }

    @Test func persistsValues() {
        let defaults = freshDefaults()
        let custom = Shortcut(keyCode: UInt32(kVK_F13), carbonModifiers: 0)
        let prefs = Preferences(defaults: defaults)
        prefs.playSounds = false
        prefs.toggleShortcut = custom
        prefs.pttShortcut = custom
        let reloaded = Preferences(defaults: defaults)
        #expect(!reloaded.playSounds)
        #expect(reloaded.toggleShortcut == custom)
        #expect(reloaded.pttShortcut == custom)
    }
}
