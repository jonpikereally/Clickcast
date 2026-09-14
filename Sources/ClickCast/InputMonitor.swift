import AppKit

/// Global event monitors. Mouse events work without permission; key events need Accessibility.
final class InputMonitor {
    var onMouseMove: ((NSPoint) -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?
    var onFlagsChanged: ((NSEvent) -> Void)?

    private var mouseMonitors: [Any] = []
    private var keyMonitors: [Any] = []
    private var pollTimer: Timer?
    private var lastPoint = NSPoint(x: -1, y: -1)

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        startMouse()
        startKeys()
    }

    private func startMouse() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            self?.reportMouse(NSEvent.mouseLocation)
        }) { mouseMonitors.append(m) }

        let downMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: downMask, handler: { [weak self] e in
            self?.reportMouse(NSEvent.mouseLocation)
            self?.onMouseDown?(e)
        }) { mouseMonitors.append(m) }

        let upMask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: upMask, handler: { [weak self] e in
            self?.onMouseUp?(e)
        }) { mouseMonitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            self?.onScroll?(e)
        }) { mouseMonitors.append(m) }

        // Fallback poll so the ring never gets stranded if an app swallows mouse-moved events.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.reportMouse(NSEvent.mouseLocation)
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func reportMouse(_ p: NSPoint) {
        guard p != lastPoint else { return }
        lastPoint = p
        onMouseMove?(p)
    }

    /// (Re)install the key monitors. Call again after Accessibility is granted.
    func startKeys() {
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors.removeAll()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            self?.onKeyDown?(e)
        }) { keyMonitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.onFlagsChanged?(e)
        }) { keyMonitors.append(m) }
    }
}
