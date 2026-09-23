import AppKit
import MicMuteCore

/// Plays a short sound when the user toggles mute. Push-to-talk stays silent.
@MainActor
final class Feedback {
    private let prefs: Preferences

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    func play(_ change: MuteState.Change) {
        guard prefs.playSounds, change.mutedChanged, !change.viaPTT else { return }
        NSSound(named: change.snapshot.muted ? "Pop" : "Tink")?.play()
    }
}
