import MicMuteCore
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    enum ShortcutTarget: Equatable {
        case toggle, pushToTalk
    }

    private let prefs: Preferences
    private let onShortcutsChanged: () -> Void
    private let onRecordingChanged: (Bool) -> Void

    @Published private(set) var toggleShortcut: Shortcut
    @Published private(set) var pttShortcut: Shortcut
    @Published var playSounds: Bool {
        didSet { prefs.playSounds = playSounds }
    }
    @Published private(set) var launchAtLogin = false
    /// A real failure from the last register/unregister attempt; persists until the next attempt.
    @Published private(set) var loginError: String?
    /// Reflects current `needsApproval` state; clears itself once approval is no longer needed.
    @Published private(set) var loginHint: String?
    @Published private(set) var recordingTarget: ShortcutTarget?

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
        loginHint = LoginItem.needsApproval ? "Approve MicMute in System Settings → General → Login Items." : nil
    }

    /// Starts (or switches) recording. Only one target records at a time: switching targets
    /// silently hands the recorder over without re-toggling the global hotkey suspension.
    func beginRecording(_ target: ShortcutTarget) {
        if recordingTarget == nil { onRecordingChanged(true) }
        recordingTarget = target
    }

    func endRecording() {
        guard recordingTarget != nil else { return }
        recordingTarget = nil
        onRecordingChanged(false)
    }
}
