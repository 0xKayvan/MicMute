import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "MicMute Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
    }

    func show() {
        model.refreshLoginStatus()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // A recording left in progress would otherwise leave global hotkeys suspended forever.
        model.endRecording()
    }
}
