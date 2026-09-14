import AppKit

/// The dark pill that shows the current chord / typed text.
final class HUDView: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var dimmed = false { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 30 { didSet { needsDisplay = true } }

    private var padX: CGFloat { fontSize * 0.7 }
    private var padY: CGFloat { fontSize * 0.35 }

    override var isFlipped: Bool { true }

    private var attributed: NSAttributedString {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: dimmed ? NSColor(white: 1, alpha: 0.55) : NSColor.white,
            .kern: fontSize * 0.06,
        ])
    }

    var pillSize: NSSize {
        let s = attributed.size()
        return NSSize(width: ceil(s.width + padX * 2), height: ceil(s.height + padY * 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(bounds.height / 2, fontSize * 0.5)
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSColor(white: 0.07, alpha: 0.86).setFill()
        bg.fill()
        NSColor(white: 1, alpha: 0.18).setStroke()
        bg.lineWidth = 1
        bg.stroke()
        attributed.draw(at: NSPoint(x: padX, y: padY))
    }
}

/// Non-activating panel anchored to a screen edge. Fades out after a short hold.
final class KeystrokeHUD {
    private let panel: NSPanel
    private let view = HUDView()
    private var hideTimer: Timer?

    private enum Mode { case none, typing, chord, modifiersOnly }
    private var mode: Mode = .none
    private var typingBuffer = ""
    private var lastChord = ""
    private var repeatCount = 1
    private var lastShownAt = Date.distantPast
    private var lastScrollAt = Date.distantPast
    private var heldModifiers = ""

    private let holdSeconds: TimeInterval = 1.6
    private let maxTyping = 26

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
        panel.alphaValue = 0
        applySettings()
    }

    func applySettings() {
        view.fontSize = Settings.shared.hudSize.fontSize
        if mode != .none { layout() }
    }

    // MARK: - Events

    func keyDown(_ e: NSEvent) {
        guard Settings.shared.keystrokes else { return }
        let flags = e.modifierFlags
        let isShortcut = KeyFormatter.hasCommandControlOption(flags) || KeyFormatter.isSpecial(e)

        if isShortcut {
            let chord = KeyFormatter.chord(e)
            guard !chord.isEmpty else { return }
            if chord == lastChord, Date().timeIntervalSince(lastShownAt) < holdSeconds {
                repeatCount += 1
            } else {
                repeatCount = 1
            }
            lastChord = chord
            typingBuffer = ""
            mode = .chord
            show(repeatCount > 1 ? "\(chord) ×\(repeatCount)" : chord, dimmed: false, hold: holdSeconds)
            return
        }

        guard !Settings.shared.shortcutsOnly else { return }
        guard let chars = e.characters, !chars.isEmpty, KeyFormatter.isPrintable(chars) else { return }
        if mode != .typing { typingBuffer = "" }
        mode = .typing
        lastChord = ""
        typingBuffer += chars
        if typingBuffer.count > maxTyping {
            typingBuffer = String(typingBuffer.suffix(maxTyping))
        }
        show(typingBuffer, dimmed: false, hold: holdSeconds)
    }

    func flagsChanged(_ e: NSEvent) {
        guard Settings.shared.keystrokes else { return }
        heldModifiers = KeyFormatter.modifiers(e.modifierFlags)
        if heldModifiers.isEmpty {
            if mode == .modifiersOnly { scheduleHide(after: 0.25) }
            return
        }
        // Don't stomp on a chord that's still on screen; the hide timer re-checks held modifiers.
        if mode == .none || mode == .modifiersOnly {
            mode = .modifiersOnly
            lastChord = ""
            show(heldModifiers, dimmed: true, hold: nil)
        }
    }

    /// For clicks: "Right Click", "⌘ Click", "Double Click".
    func mouseDown(_ e: NSEvent) {
        guard Settings.shared.keystrokes, Settings.shared.clicksInHUD else { return }
        let mods = KeyFormatter.modifiers(e.modifierFlags)
        var name: String
        switch e.type {
        case .rightMouseDown: name = "Right Click"
        case .otherMouseDown: name = "Middle Click"
        default:
            switch e.clickCount {
            case 2: name = "Double Click"
            case 3: name = "Triple Click"
            default: name = "Click"
            }
        }
        // A plain single left click is already shown by the ripple.
        if name == "Click" && mods.isEmpty { return }
        message(mods.isEmpty ? name : "\(mods) \(name)")
    }

    func scroll(_ e: NSEvent) {
        guard Settings.shared.keystrokes, Settings.shared.clicksInHUD else { return }
        let mods = KeyFormatter.modifiers(e.modifierFlags)
        guard !mods.isEmpty, Date().timeIntervalSince(lastScrollAt) > 0.4 else { return }
        lastScrollAt = Date()
        message("\(mods) Scroll")
    }

    /// Arbitrary text from the control server, shown even when keystrokes are off.
    func showCustom(_ text: String, seconds: Double) {
        mode = .chord
        lastChord = ""
        typingBuffer = ""
        show(text, dimmed: false, hold: max(0.5, seconds))
    }

    private func message(_ s: String) {
        mode = .chord
        lastChord = ""
        typingBuffer = ""
        show(s, dimmed: false, hold: 1.2)
    }

    func hideNow() {
        hideTimer?.invalidate()
        mode = .none
        typingBuffer = ""
        lastChord = ""
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    // MARK: - Display

    private func show(_ text: String, dimmed: Bool, hold: TimeInterval?) {
        hideTimer?.invalidate()
        lastShownAt = Date()
        view.text = text
        view.dimmed = dimmed
        layout()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        if let hold { scheduleHide(after: hold) }
    }

    private func scheduleHide(after: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
            self?.hideTimerFired()
        }
    }

    private func hideTimerFired() {
        // If modifiers are still held, fall back to showing them dimmed instead of vanishing.
        if !heldModifiers.isEmpty, Settings.shared.keystrokes {
            mode = .modifiersOnly
            lastChord = ""
            show(heldModifiers, dimmed: true, hold: nil)
            return
        }
        mode = .none
        typingBuffer = ""
        lastChord = ""
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.mode == .none else { return }
            self.panel.orderOut(nil)
        })
    }

    private func layout() {
        let size = view.pillSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSPointInRect(mouse, $0.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let margin: CGFloat = 28
        var origin = NSPoint.zero
        switch Settings.shared.hudPosition {
        case .bottomLeft:   origin = NSPoint(x: vf.minX + margin, y: vf.minY + margin)
        case .bottomCenter: origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + margin)
        case .bottomRight:  origin = NSPoint(x: vf.maxX - margin - size.width, y: vf.minY + margin)
        case .topLeft:      origin = NSPoint(x: vf.minX + margin, y: vf.maxY - margin - size.height)
        case .topCenter:    origin = NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - margin - size.height)
        case .topRight:     origin = NSPoint(x: vf.maxX - margin - size.width, y: vf.maxY - margin - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
