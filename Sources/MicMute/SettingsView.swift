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
                    ShortcutRecorder(model: model, target: .toggle)
                }
                LabeledContent("Push to talk (hold)") {
                    ShortcutRecorder(model: model, target: .pushToTalk)
                }
            }
            Section("General") {
                Toggle("Play sound on mute/unmute", isOn: $model.playSounds)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if let hint = model.loginHint {
                    Text(hint).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

/// Click, then type a key combo. Esc cancels. Global hotkeys are suspended while recording.
/// Recording state lives in `SettingsModel` so only one recorder can record at a time, and so
/// the window can force an in-progress recording to end (e.g. on close) even if this view never
/// gets an `.onDisappear`.
struct ShortcutRecorder: View {
    @ObservedObject var model: SettingsModel
    let target: SettingsModel.ShortcutTarget

    @State private var monitor: Any?

    private var shortcut: Shortcut {
        target == .toggle ? model.toggleShortcut : model.pttShortcut
    }
    private var conflict: Shortcut {
        target == .toggle ? model.pttShortcut : model.toggleShortcut
    }
    private var recording: Bool { model.recordingTarget == target }

    var body: some View {
        Button(recording ? "Type shortcut…" : shortcut.displayString) {
            recording ? stop() : start()
        }
        .frame(minWidth: 150)
        .onChange(of: model.recordingTarget) { newTarget in
            // Another recorder took over (or recording ended elsewhere): drop our monitor.
            if newTarget != target { removeMonitor() }
        }
        .onDisappear { stop() }
    }

    private func start() {
        model.beginRecording(target)
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
            apply(candidate)
            stop()
            return nil
        }
    }

    private func apply(_ candidate: Shortcut) {
        switch target {
        case .toggle: model.setToggleShortcut(candidate)
        case .pushToTalk: model.setPTTShortcut(candidate)
        }
    }

    private func stop() {
        removeMonitor()
        if recording { model.endRecording() }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
