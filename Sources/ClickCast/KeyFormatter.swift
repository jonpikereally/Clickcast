import AppKit
import Carbon

/// Turns NSEvents into the symbols viewers expect to see: ⌃ ⌥ ⇧ ⌘ + key.
enum KeyFormatter {
    /// Modifier symbols in Apple's canonical display order.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    static func hasCommandControlOption(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.command, .control, .option]).isEmpty
    }

    static let specialKeys: [UInt16: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 71: "⌧",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func isSpecial(_ e: NSEvent) -> Bool { specialKeys[e.keyCode] != nil }

    /// The key's name as shown in a chord: special-key glyph, else the unshifted character, uppercased.
    static func keyName(_ e: NSEvent) -> String {
        if let s = specialKeys[e.keyCode] { return s }
        if let u = unshiftedCharacter(keyCode: e.keyCode), !u.isEmpty, isPrintable(u) {
            return u.uppercased()
        }
        guard let chars = e.charactersIgnoringModifiers, !chars.isEmpty, isPrintable(chars) else { return "" }
        return chars.uppercased()
    }

    /// Full chord string, e.g. "⇧⌘S".
    static func chord(_ e: NSEvent) -> String {
        modifiers(e.modifierFlags) + keyName(e)
    }

    static func isPrintable(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        return scalar.value >= 32 && scalar.value != 127 && !(0xF700...0xF8FF).contains(scalar.value)
    }

    /// The character a key produces with no modifiers, using the current keyboard layout.
    /// Needed so ⇧1 shows as "⇧1" rather than "⇧!".
    static func unshiftedCharacter(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status: OSStatus = data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(-1) }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
