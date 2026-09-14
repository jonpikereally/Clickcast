import AppKit
// Renders AppIcon.iconset PNGs: dark rounded square, yellow cursor ring, white arrow cursor.
let sizes: [(String, Int)] = [("16",16),("16@2x",32),("32",32),("32@2x",64),("128",128),("128@2x",256),("256",256),("256@2x",512),("512",512),("512@2x",1024)]
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.04, dy: s * 0.04)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(starting: NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1), ending: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))!.draw(in: bg, angle: -90)
    // ripple rings
    let c = NSPoint(x: s * 0.46, y: s * 0.52)
    let yellow = NSColor(red: 1, green: 0.84, blue: 0.1, alpha: 1)
    for (r, a, w) in [(0.30, 0.25, 0.02), (0.22, 0.6, 0.03)] as [(CGFloat, CGFloat, CGFloat)] {
        let p = NSBezierPath(ovalIn: NSRect(x: c.x - s * r, y: c.y - s * r, width: s * r * 2, height: s * r * 2))
        yellow.withAlphaComponent(a).setStroke(); p.lineWidth = s * w; p.stroke()
    }
    let inner = NSBezierPath(ovalIn: NSRect(x: c.x - s * 0.15, y: c.y - s * 0.15, width: s * 0.30, height: s * 0.30))
    yellow.withAlphaComponent(0.35).setFill(); inner.fill()
    yellow.setStroke(); inner.lineWidth = s * 0.03; inner.stroke()
    // arrow cursor
    let a = NSBezierPath()
    let ox = c.x - s * 0.02, oy = c.y + s * 0.04
    let pts: [(CGFloat, CGFloat)] = [(0,0),(0,-0.36),(0.09,-0.27),(0.15,-0.40),(0.20,-0.38),(0.14,-0.25),(0.26,-0.25)]
    a.move(to: NSPoint(x: ox, y: oy))
    for (dx, dy) in pts.dropFirst() { a.line(to: NSPoint(x: ox + s * dx, y: oy + s * dy)) }
    a.close()
    NSColor.white.setFill(); a.fill()
    NSColor.black.setStroke(); a.lineWidth = max(1, s * 0.018); a.lineJoinStyle = .round; a.stroke()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    rep.size = NSSize(width: s, height: s)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
print("icons written")
