import AppKit
import Carbon.HIToolbox
import MicMuteCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Toggle mute") {
                    ShortcutRecorder(shortcut: model.toggleShortcut, conflict: model.pttShortcut,
                                     onChange: model.setToggleShortcut, onRecordingChanged: model.onRecordingChanged)
                }
                LabeledContent("Push to talk (hold)") {
                    ShortcutRecorder(shortcut: model.pttShortcut, conflict: model.toggleShortcut,
                                     onChange: model.setPTTShortcut, onRecordingChanged: model.onRecordingChanged)
                }
            }
            Section("General") {
                Toggle("Play sound on mute/unmute", isOn: $model.playSounds)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

/// Click, then type a key combo. Esc cancels. Global hotkeys are suspended while recording.
struct ShortcutRecorder: View {
    let shortcut: Shortcut
    let conflict: Shortcut
    let onChange: (Shortcut) -> Void
    let onRecordingChanged: (Bool) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type shortcut…" : shortcut.displayString) {
            recording ? stop() : start()
        }
        .frame(minWidth: 150)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let candidate = Shortcut(keyCode: UInt32(event.keyCode), cocoaModifiers: flags.rawValue)
            guard candidate.isValid, candidate != conflict else {
                NSSound.beep()
                return nil
            }
            onChange(candidate)
            stop()
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        onRecordingChanged(false)
    }
}
