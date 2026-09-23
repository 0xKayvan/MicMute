import Carbon.HIToolbox
import MicMuteCore
import os

/// System-wide hotkeys via Carbon `RegisterEventHotKey`. Delivers both key-down and key-up
/// (needed for push-to-talk) and needs no Accessibility permission.
@MainActor
final class HotkeyManager {
    private struct Handlers {
        let onDown: () -> Void
        let onUp: () -> Void
    }

    private static let signature: OSType = 0x4D4D_5554 // 'MMUT'
    private let log = Logger(subsystem: "xyz.kayvan.micmute", category: "hotkeys")
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: Handlers] = [:]
    private var pressed: Set<UInt32> = []
    private var eventHandler: EventHandlerRef?

    init() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let isDown = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.handle(id: hotKeyID.id, isDown: isDown) }
            return noErr
        }, eventTypes.count, &eventTypes, context, &eventHandler)
        if status != noErr { log.error("InstallEventHandler failed: \(status)") }
    }

    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> Bool {
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey \(shortcut.displayString) failed: \(status)")
            return false
        }
        refs[id] = ref
        handlers[id] = Handlers(onDown: onDown, onUp: onUp)
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        let removed = handlers.removeValue(forKey: id)
        // A hold in progress must still be released, or push-to-talk would stick.
        if pressed.remove(id) != nil { removed?.onUp() }
    }

    func unregisterAll() {
        Array(refs.keys).forEach { unregister(id: $0) }
    }

    private func handle(id: UInt32, isDown: Bool) {
        guard let handler = handlers[id] else { return }
        if isDown {
            // Ignore key auto-repeat so a held toggle key doesn't flap.
            guard pressed.insert(id).inserted else { return }
            handler.onDown()
        } else {
            guard pressed.remove(id) != nil else { return }
            handler.onUp()
        }
    }
}
