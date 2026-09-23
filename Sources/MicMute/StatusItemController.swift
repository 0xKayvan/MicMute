import AppKit
import MicMuteCore

/// Menu bar icon. Left-click toggles mute; right-click (or ⌃/⌥-click) opens the menu.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let state: MuteState
    private let mic: MicController
    private let onSettings: () -> Void
    var bridgeAvailable = true

    init(state: MuteState, mic: MicController, onSettings: @escaping () -> Void) {
        self.state = state
        self.mic = mic
        self.onSettings = onSettings
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        update()
    }

    func update() {
        let muted = state.snapshot.muted
        let label = muted ? "Microphones muted" : "Microphones live"
        var image = NSImage(systemSymbolName: muted ? "mic.slash.fill" : "mic.fill", accessibilityDescription: label)
        if muted {
            image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        } else {
            image?.isTemplate = true
        }
        item.button?.image = image
        item.button?.toolTip = label
    }

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        if event?.type == .rightMouseUp || flags.contains(.control) || flags.contains(.option) {
            showMenu()
        } else {
            state.toggle()
        }
    }

    private func showMenu() {
        item.menu = buildMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let muted = state.snapshot.muted
        menu.addItem(disabledItem(muted ? "Microphones: Muted" : "Microphones: Live"))
        menu.addItem(actionItem(muted ? "Unmute" : "Mute", #selector(toggleClicked)))
        menu.addItem(.separator())
        menu.addItem(disabledItem("Input Devices"))
        let statuses = mic.deviceStatuses
        if statuses.isEmpty { menu.addItem(disabledItem("    No input devices")) }
        statuses.forEach { menu.addItem(disabledItem("    " + $0.summary)) }
        if !bridgeAvailable {
            menu.addItem(.separator())
            menu.addItem(disabledItem("⚠︎ Stream Deck bridge unavailable"))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Settings…", #selector(settingsClicked), key: ","))
        menu.addItem(actionItem("Quit MicMute", #selector(quitClicked), key: "q"))
        return menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleClicked() { state.toggle() }
    @objc private func settingsClicked() { onSettings() }
    @objc private func quitClicked() { NSApp.terminate(nil) }
}
