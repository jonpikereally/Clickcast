import AppKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("ClickCast.settingsChanged")
}

enum HUDPosition: String, CaseIterable {
    case bottomLeft, bottomCenter, bottomRight, topLeft, topCenter, topRight
    var title: String {
        switch self {
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        }
    }
}

enum CursorSize: String, CaseIterable {
    case small, medium, large, huge
    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .huge: return "Huge"
        }
    }
    var radius: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 26
        case .large: return 36
        case .huge: return 50
        }
    }
}

enum HUDSize: String, CaseIterable {
    case small, medium, large
    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    var fontSize: CGFloat {
        switch self {
        case .small: return 22
        case .medium: return 30
        case .large: return 40
        }
    }
}

enum HighlightColor: String, CaseIterable {
    case yellow, orange, green, blue, pink, white
    var title: String {
        switch self {
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .white: return "White"
        }
    }
    var color: NSColor {
        switch self {
        case .yellow: return NSColor(red: 1.00, green: 0.84, blue: 0.10, alpha: 1)
        case .orange: return NSColor(red: 1.00, green: 0.55, blue: 0.15, alpha: 1)
        case .green:  return NSColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 1)
        case .blue:   return NSColor(red: 0.30, green: 0.65, blue: 1.00, alpha: 1)
        case .pink:   return NSColor(red: 1.00, green: 0.40, blue: 0.70, alpha: 1)
        case .white:  return NSColor(white: 1, alpha: 1)
        }
    }
}

/// All user preferences, backed by UserDefaults. Any change posts `.settingsChanged`.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }
    private func store(_ value: Any?, _ key: String) {
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    var cursorHighlight: Bool {
        get { bool("cursorHighlight", true) }
        set { store(newValue, "cursorHighlight") }
    }
    var clickRipples: Bool {
        get { bool("clickRipples", true) }
        set { store(newValue, "clickRipples") }
    }
    var keystrokes: Bool {
        get { bool("keystrokes", true) }
        set { store(newValue, "keystrokes") }
    }
    /// true = only show chords with ⌘/⌃/⌥ and special keys; false = show everything typed.
    var shortcutsOnly: Bool {
        get { bool("shortcutsOnly", true) }
        set { store(newValue, "shortcutsOnly") }
    }
    /// Show "Right Click", "⌘ Click", "Double Click" etc. in the keystroke display.
    var clicksInHUD: Bool {
        get { bool("clicksInHUD", true) }
        set { store(newValue, "clicksInHUD") }
    }
    var hudPosition: HUDPosition {
        get { HUDPosition(rawValue: d.string(forKey: "hudPosition") ?? "") ?? .bottomCenter }
        set { store(newValue.rawValue, "hudPosition") }
    }
    var hudSize: HUDSize {
        get { HUDSize(rawValue: d.string(forKey: "hudSize") ?? "") ?? .medium }
        set { store(newValue.rawValue, "hudSize") }
    }
    var cursorSize: CursorSize {
        get { CursorSize(rawValue: d.string(forKey: "cursorSize") ?? "") ?? .medium }
        set { store(newValue.rawValue, "cursorSize") }
    }
    var highlightColor: HighlightColor {
        get { HighlightColor(rawValue: d.string(forKey: "highlightColor") ?? "") ?? .yellow }
        set { store(newValue.rawValue, "highlightColor") }
    }
}
