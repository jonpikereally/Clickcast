import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayController()
    private let hud = KeystrokeHUD()
    private let input = InputMonitor()
    private var paused = false
    private var trusted = false
    private var trustTimer: Timer?
    private var server: ControlServer?

    var isPaused: Bool { paused }
    var isTrusted: Bool { trusted }

    func setPaused(_ p: Bool) {
        guard p != paused else { return }
        togglePause()
    }

    /// Flash arbitrary text in the keystroke pill (Stream Deck "Show Message" action).
    func showMessage(_ text: String, seconds: Double) {
        guard !paused else { return }
        hud.showCustom(text, seconds: seconds)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("ClickCast launching v\(AppVersion.version)")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        overlay.rebuild()
        wireInput()
        input.start()
        server = ControlServer(app: self)
        server?.start()

        trusted = InputMonitor.accessibilityTrusted
        if !trusted { InputMonitor.requestAccessibility() }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkTrust()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.overlay.rebuild()
        }
        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.applySettings()
            self?.hud.applySettings()
            if !(self?.paused ?? true) && !Settings.shared.keystrokes { self?.hud.hideNow() }
        }
    }

    private func wireInput() {
        input.onMouseMove = { [weak self] p in self?.overlay.mouseMoved(p) }
        input.onMouseDown = { [weak self] e in
            guard let self, !self.paused else { return }
            self.overlay.mouseDown(e)
            self.hud.mouseDown(e)
        }
        input.onMouseUp = { [weak self] _ in self?.overlay.mouseUp() }
        input.onScroll = { [weak self] e in
            guard let self, !self.paused else { return }
            self.hud.scroll(e)
        }
        input.onKeyDown = { [weak self] e in
            guard let self else { return }
            // ⌃⌥⌘K toggles pause from anywhere.
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.keyCode == 40, f.contains([.control, .option, .command]), !f.contains(.shift) {
                self.togglePause()
                return
            }
            guard !self.paused else { return }
            self.hud.keyDown(e)
        }
        input.onFlagsChanged = { [weak self] e in
            guard let self, !self.paused else { return }
            self.hud.flagsChanged(e)
        }
    }

    private func checkTrust() {
        let now = InputMonitor.accessibilityTrusted
        if now != trusted {
            trusted = now
            if now { input.startKeys() }
            updateIcon()
        }
    }

    // MARK: - Pause

    @objc private func togglePause() {
        paused.toggle()
        overlay.setEnabled(!paused)
        hud.hideNow()
        updateIcon()
    }

    private func updateIcon() {
        let name = paused ? "cursorarrow.slash" : "cursorarrow.click.2"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "ClickCast")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.toolTip = paused ? "ClickCast (paused)" : "ClickCast"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        let title = NSMenuItem(title: "ClickCast \(AppVersion.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !trusted {
            let warn = NSMenuItem(title: "⚠️ Grant Accessibility to show keystrokes…", action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        menu.addItem(check(paused ? "Resume" : "Pause", on: paused, #selector(togglePause), key: "k", mods: [.control, .option, .command]))
        menu.addItem(.separator())

        menu.addItem(check("Highlight Cursor", on: s.cursorHighlight, #selector(toggleCursor)))
        menu.addItem(check("Click Ripples", on: s.clickRipples, #selector(toggleRipples)))
        menu.addItem(check("Show Keystrokes", on: s.keystrokes, #selector(toggleKeystrokes)))

        let ksMenu = NSMenu()
        ksMenu.addItem(check("Shortcuts Only", on: s.shortcutsOnly, #selector(setShortcutsOnly)))
        ksMenu.addItem(check("Everything I Type", on: !s.shortcutsOnly, #selector(setAllKeys)))
        ksMenu.addItem(.separator())
        ksMenu.addItem(check("Show Clicks (Right, ⌘-Click, Double)", on: s.clicksInHUD, #selector(toggleClicksInHUD)))
        ksMenu.addItem(.separator())
        for p in HUDPosition.allCases {
            ksMenu.addItem(radio(p.title, on: s.hudPosition == p, #selector(setHUDPosition), p.rawValue))
        }
        ksMenu.addItem(.separator())
        for z in HUDSize.allCases {
            ksMenu.addItem(radio("\(z.title) Text", on: s.hudSize == z, #selector(setHUDSize), z.rawValue))
        }
        let ksItem = NSMenuItem(title: "Keystroke Display", action: nil, keyEquivalent: "")
        ksItem.submenu = ksMenu
        menu.addItem(ksItem)

        let sizeMenu = NSMenu()
        for z in CursorSize.allCases {
            sizeMenu.addItem(radio(z.title, on: s.cursorSize == z, #selector(setCursorSize), z.rawValue))
        }
        let sizeItem = NSMenuItem(title: "Cursor Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let colorMenu = NSMenu()
        for c in HighlightColor.allCases {
            let item = radio(c.title, on: s.highlightColor == c, #selector(setColor), c.rawValue)
            item.image = swatch(c.color)
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Highlight Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(.separator())
        if #available(macOS 13.0, *) {
            let on = SMAppService.mainApp.status == .enabled
            menu.addItem(check("Launch at Login", on: on, #selector(toggleLaunchAtLogin)))
        }
        let quit = NSMenuItem(title: "Quit ClickCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func check(_ title: String, on: Bool, _ sel: Selector, key: String = "", mods: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func radio(_ title: String, on: Bool, _ sel: Selector, _ value: String) -> NSMenuItem {
        let item = check(title, on: on, sel)
        item.representedObject = value
        return item
    }

    private func swatch(_ color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            NSColor(white: 0, alpha: 0.3).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
            return true
        }
        return img
    }

    // MARK: - Actions

    @objc private func toggleCursor() { Settings.shared.cursorHighlight.toggle() }
    @objc private func toggleRipples() { Settings.shared.clickRipples.toggle() }
    @objc private func toggleKeystrokes() { Settings.shared.keystrokes.toggle() }
    @objc private func setShortcutsOnly() { Settings.shared.shortcutsOnly = true }
    @objc private func setAllKeys() { Settings.shared.shortcutsOnly = false }
    @objc private func toggleClicksInHUD() { Settings.shared.clicksInHUD.toggle() }
    @objc private func setHUDPosition(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let p = HUDPosition(rawValue: v) { Settings.shared.hudPosition = p }
    }
    @objc private func setHUDSize(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let z = HUDSize(rawValue: v) { Settings.shared.hudSize = z }
    }
    @objc private func setCursorSize(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let z = CursorSize(rawValue: v) { Settings.shared.cursorSize = z }
    }
    @objc private func setColor(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let c = HighlightColor(rawValue: v) { Settings.shared.highlightColor = c }
    }

    @objc private func openAccessibility() {
        InputMonitor.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
