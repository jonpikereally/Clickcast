import AppKit
import QuartzCore

/// Layer-hosting view that draws the cursor ring and click ripples.
final class CursorView: NSView {
    private let ring = CAShapeLayer()
    private var radius: CGFloat = 26
    private var color: NSColor = .yellow
    private(set) var ringVisible = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        ring.lineWidth = 2.5
        ring.zPosition = 10
        root.addSublayer(ring)
        applyStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func circle(_ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
    }

    func configure(radius: CGFloat, color: NSColor) {
        self.radius = radius
        self.color = color
        applyStyle()
    }

    private func applyStyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.path = circle(radius)
        ring.fillColor = color.withAlphaComponent(0.28).cgColor
        ring.strokeColor = color.withAlphaComponent(0.95).cgColor
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOpacity = 0.35
        ring.shadowRadius = 3
        ring.shadowOffset = .zero
        CATransaction.commit()
    }

    func setRingVisible(_ visible: Bool) {
        ringVisible = visible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = !visible
        CATransaction.commit()
    }

    func move(to p: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = p
        CATransaction.commit()
    }

    func setPressed(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        ring.transform = pressed ? CATransform3DMakeScale(0.8, 0.8, 1) : CATransform3DIdentity
        ring.fillColor = color.withAlphaComponent(pressed ? 0.55 : 0.28).cgColor
        CATransaction.commit()
    }

    func ripple(at p: CGPoint, color: NSColor) {
        let l = CAShapeLayer()
        let r0 = radius * 0.8
        let r1 = radius * 2.8
        l.position = p
        l.path = circle(r0)
        l.fillColor = color.withAlphaComponent(0.30).cgColor
        l.strokeColor = color.cgColor
        l.lineWidth = 4
        l.zPosition = 5
        layer?.addSublayer(l)

        let path = CABasicAnimation(keyPath: "path")
        path.fromValue = circle(r0)
        path.toValue = circle(r1)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.0
        let width = CABasicAnimation(keyPath: "lineWidth")
        width.fromValue = 4
        width.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [path, opacity, width]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(group, forKey: "ripple")
        CATransaction.commit()
    }
}

/// One transparent, click-through window per screen, above everything (including full-screen apps).
final class OverlayWindow: NSWindow {
    let cursorView: CursorView

    init(screen: NSScreen) {
        cursorView = CursorView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = cursorView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Owns the overlay windows and routes mouse events to the right screen.
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var enabled = true
    private var lastPoint = NSPoint.zero

    func rebuild() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
        applySettings()
        setEnabled(enabled)
    }

    func applySettings() {
        let s = Settings.shared
        for w in windows {
            w.cursorView.configure(radius: s.cursorSize.radius, color: s.highlightColor.color)
            w.cursorView.setRingVisible(s.cursorHighlight)
        }
        mouseMoved(lastPoint)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        for w in windows {
            if on { w.orderFrontRegardless() } else { w.orderOut(nil) }
        }
    }

    private func window(containing p: NSPoint) -> OverlayWindow? {
        windows.first { NSPointInRect(p, $0.frame) } ?? windows.first
    }

    func mouseMoved(_ p: NSPoint) {
        lastPoint = p
        guard enabled, Settings.shared.cursorHighlight else { return }
        let target = window(containing: p)
        for w in windows {
            if w === target {
                w.cursorView.setRingVisible(true)
                w.cursorView.move(to: CGPoint(x: p.x - w.frame.minX, y: p.y - w.frame.minY))
            } else {
                w.cursorView.setRingVisible(false)
            }
        }
    }

    func mouseDown(_ e: NSEvent) {
        guard enabled else { return }
        let p = NSEvent.mouseLocation
        guard let w = window(containing: p) else { return }
        let local = CGPoint(x: p.x - w.frame.minX, y: p.y - w.frame.minY)
        if Settings.shared.cursorHighlight { w.cursorView.setPressed(true) }
        guard Settings.shared.clickRipples else { return }
        let color: NSColor
        switch e.type {
        case .rightMouseDown: color = NSColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 1)
        case .otherMouseDown: color = NSColor(red: 0.35, green: 0.95, blue: 0.45, alpha: 1)
        default: color = Settings.shared.highlightColor.color
        }
        w.cursorView.ripple(at: local, color: color)
    }

    func mouseUp() {
        for w in windows { w.cursorView.setPressed(false) }
    }
}
