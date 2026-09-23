import Carbon.HIToolbox

/// A global keyboard shortcut: a virtual key code plus Carbon modifier mask.
public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// - Parameter cocoaModifiers: `NSEvent.ModifierFlags.rawValue`.
    public init(keyCode: UInt32, cocoaModifiers: UInt) {
        var modifiers: UInt32 = 0
        if cocoaModifiers & (1 << 18) != 0 { modifiers |= UInt32(controlKey) }
        if cocoaModifiers & (1 << 19) != 0 { modifiers |= UInt32(optionKey) }
        if cocoaModifiers & (1 << 17) != 0 { modifiers |= UInt32(shiftKey) }
        if cocoaModifiers & (1 << 20) != 0 { modifiers |= UInt32(cmdKey) }
        self.init(keyCode: keyCode, carbonModifiers: modifiers)
    }

    public static let defaultToggle = Shortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(controlKey | optionKey))
    public static let defaultPushToTalk = Shortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey))

    /// Plain or shift-only keys would swallow normal typing (e.g. capitals), so non-function
    /// keys need at least one of ⌃/⌥/⌘; function keys are fine alone.
    public var isValid: Bool {
        carbonModifiers & UInt32(controlKey | optionKey | cmdKey) != 0 || Self.functionKeyNames[Int(keyCode)] != nil
    }

    public var modifierSymbols: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    public var displayString: String { modifierSymbols + Self.keyName(for: keyCode) }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19",
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        let code = Int(keyCode)
        if let name = specialKeyNames[code] ?? functionKeyNames[code] { return name }
        return layoutCharacter(for: keyCode) ?? "#\(keyCode)"
    }

    /// Character the key produces on the current keyboard layout (e.g. "M" on QWERTY).
    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
