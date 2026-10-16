import AppKit
import MicMuteCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "xyz.kayvan.micmute", category: "app")
    private let prefs = Preferences()
    private var mic: MicController!
    private var state: MuteState!
    private var router: CommandRouter!
    private var bridge: BridgeServer!
    private var statusItem: StatusItemController!
    private var feedback: Feedback!
    private let hotkeys = HotkeyManager()
    private var settings: SettingsWindowController?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mic = MicController(audio: CoreAudioSystem())
        self.mic = mic
        // Start muted only if the mics already are (e.g. after a crash), so the icon tells the truth.
        state = MuteState(initiallyMuted: mic.allMuted) { mic.apply(muted: $0) }
        if state.effectiveMuted { mic.apply(muted: true) }

        feedback = Feedback(prefs: prefs)
        router = CommandRouter(state: state)
        statusItem = StatusItemController(state: state, mic: mic, onSettings: { [weak self] in self?.showSettings() })
        mic.onWarningsChanged = { [weak self] in self?.statusItem.update() }
        bridge = BridgeServer(initialState: BridgeMessage.state(state.snapshot))

        state.addObserver { [weak self] change in
            guard let self else { return }
            statusItem.update()
            bridge.broadcast(BridgeMessage.state(change.snapshot))
            feedback.play(change)
        }

        bridge.onCommand = { [weak self] command, client in
            MainActor.assumeIsolated { self?.router.handle(command, from: client) }
        }
        bridge.onClientDisconnected = { [weak self] client in
            MainActor.assumeIsolated { self?.router.clientDisconnected(client) }
        }
        bridge.onStatusChange = { [weak self] listening in
            MainActor.assumeIsolated { self?.statusItem.bridgeAvailable = listening }
        }
        do {
            try bridge.start()
        } catch {
            log.error("Bridge failed to start: \(error.localizedDescription)")
            statusItem.bridgeAvailable = false
        }
        registerHotkeys()
        installSIGTERMHandler()
    }

    /// SIGTERM (e.g. `pkill`, logout) would otherwise kill the process without
    /// `applicationWillTerminate`, leaving mics muted. Route it through a normal quit.
    private func installSIGTERMHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigtermSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave mics muted without the app running to show it.
        if state.effectiveMuted { mic.apply(muted: false) }
    }

    private func registerHotkeys() {
        let toggleOK = hotkeys.register(id: 1, shortcut: prefs.toggleShortcut,
                                        onDown: { [weak self] in self?.state.toggle() },
                                        onUp: {})
        let pttOK = hotkeys.register(id: 2, shortcut: prefs.pttShortcut,
                                     onDown: { [weak self] in self?.state.pttBegin(source: "hotkey") },
                                     onUp: { [weak self] in self?.state.pttEnd(source: "hotkey") })
        if !toggleOK || !pttOK { log.error("A global shortcut could not be registered; it may be in use by another app.") }
    }

    private func showSettings() {
        if settings == nil {
            let model = SettingsModel(
                prefs: prefs,
                onShortcutsChanged: { [weak self] in self?.registerHotkeys() },
                onRecordingChanged: { [weak self] recording in
                    if recording { self?.hotkeys.unregisterAll() } else { self?.registerHotkeys() }
                }
            )
            settings = SettingsWindowController(model: model)
        }
        settings?.show()
    }
}
