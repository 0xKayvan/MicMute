import MicMuteCore
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    private let prefs: Preferences
    private let onShortcutsChanged: () -> Void
    let onRecordingChanged: (Bool) -> Void

    @Published private(set) var toggleShortcut: Shortcut
    @Published private(set) var pttShortcut: Shortcut
    @Published var playSounds: Bool {
        didSet { prefs.playSounds = playSounds }
    }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginError: String?

    init(prefs: Preferences, onShortcutsChanged: @escaping () -> Void, onRecordingChanged: @escaping (Bool) -> Void) {
        self.prefs = prefs
        self.onShortcutsChanged = onShortcutsChanged
        self.onRecordingChanged = onRecordingChanged
        toggleShortcut = prefs.toggleShortcut
        pttShortcut = prefs.pttShortcut
        playSounds = prefs.playSounds
        refreshLoginStatus()
    }

    func setToggleShortcut(_ shortcut: Shortcut) {
        toggleShortcut = shortcut
        prefs.toggleShortcut = shortcut
        onShortcutsChanged()
    }

    func setPTTShortcut(_ shortcut: Shortcut) {
        pttShortcut = shortcut
        prefs.pttShortcut = shortcut
        onShortcutsChanged()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
        if LoginItem.needsApproval, loginError == nil {
            loginError = "Approve MicMute in System Settings → General → Login Items."
        }
    }
}
