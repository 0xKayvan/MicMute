import AppKit
import MicMuteCore

// `MicMute --status` prints each input device and exits (handy for debugging mute support).
if CommandLine.arguments.contains("--status") {
    MainActor.assumeIsolated {
        MicController(audio: CoreAudioSystem()).deviceStatuses.forEach { print($0.summary) }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
