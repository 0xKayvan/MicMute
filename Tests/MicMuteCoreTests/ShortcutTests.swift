import Carbon.HIToolbox
import Testing
import MicMuteCore

@Suite struct ShortcutTests {
    // NSEvent.ModifierFlags raw values
    let control: UInt = 1 << 18, option: UInt = 1 << 19, shift: UInt = 1 << 17, command: UInt = 1 << 20

    @Test func convertsCocoaModifiersToCarbon() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_M), cocoaModifiers: control | option)
        #expect(shortcut == .defaultToggle)
        #expect(shortcut.carbonModifiers == UInt32(controlKey | optionKey))
    }

    @Test func modifierSymbolsUseStandardOrder() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_Space), cocoaModifiers: command | shift | option | control)
        #expect(shortcut.modifierSymbols == "⌃⌥⇧⌘")
    }

    @Test func displaysSpecialAndFunctionKeys() {
        #expect(Shortcut.defaultPushToTalk.displayString == "⌃⌥Space")
        #expect(Shortcut(keyCode: UInt32(kVK_F5), carbonModifiers: 0).displayString == "F5")
    }

    @Test func requiresModifierUnlessFunctionKey() {
        #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: 0).isValid)
        #expect(Shortcut(keyCode: UInt32(kVK_F5), carbonModifiers: 0).isValid)
        #expect(Shortcut.defaultToggle.isValid)
    }
}
