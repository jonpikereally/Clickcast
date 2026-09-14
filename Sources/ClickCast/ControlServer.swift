//  ControlServer.swift — loopback HTTP control surface for the Stream Deck plugin.
//  Bound to 127.0.0.1 only; not reachable from the network.
//
//  GET  /state                      → full state (see `state()`)
//  POST /pause    {toggle:true} | {paused:Bool}
//  POST /toggle   {key:"cursorHighlight"|"clickRipples"|"keystrokes"|"shortcutsOnly"|"clicksInHUD", on?:Bool}
//  POST /choose   {key:"cursorSize"|"highlightColor"|"hudPosition"|"hudSize", value?:String, step?:Int}
//  POST /message  {text:String, seconds?:Double}   → shows text in the keystroke pill
//  Every response is the new state.

import Foundation
import Darwin

final class ControlServer {
    static let port: UInt16 = 8766

    private var socketFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.jonpike.clickcast.control", qos: .userInitiated)
    private unowned let app: AppDelegate

    init(app: AppDelegate) { self.app = app }

    /// Plain BSD sockets: no Network.framework daemon dependency, and trivially testable.
    func start() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { NSLog("ClickCast control server: socket() failed"); return }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            NSLog("ClickCast control server: bind/listen on 127.0.0.1:\(Self.port) failed (errno \(errno))")
            close(fd)
            return
        }
        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        acceptSource = source
        NSLog("ClickCast control server listening on 127.0.0.1:\(Self.port)")
    }

    private func acceptOne() {
        let client = accept(socketFD, nil, nil)
        guard client >= 0 else { return }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        queue.async { [weak self] in self?.serve(client) }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        var parsed: (head: String, body: Data, complete: Bool)?
        while buf.count < 1 << 20 {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { break }
            buf.append(chunk, count: n)
            if let p = Self.parse(buf) {
                parsed = p
                if p.complete { break }
            }
        }
        guard let req = parsed, req.complete else { return }
        let startLine = req.head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = startLine.split(separator: " ")
        let path = parts.count > 1 ? String(parts[1]) : "/"
        let json = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? [:]

        // Settings and AppKit state live on the main thread.
        var payload: [String: Any] = [:]
        DispatchQueue.main.sync { payload = self.handle(path: path, json: json) }

        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        response.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(client, raw.baseAddress! + sent, raw.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    private static func parse(_ data: Data) -> (head: String, body: Data, complete: Bool)? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<sep.lowerBound], as: UTF8.self)
        let body = data[sep.upperBound...]
        var expected = 0
        for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            expected = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return (head, Data(body), body.count >= expected)
    }

    // MARK: - Routes

    private func handle(path: String, json: [String: Any]) -> [String: Any] {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        let s = Settings.shared
        switch route {
        case "/", "/state":
            break

        case "/pause":
            if json["toggle"] as? Bool == true { app.setPaused(!app.isPaused) }
            else if let p = json["paused"] as? Bool { app.setPaused(p) }

        case "/toggle":
            let on = json["on"] as? Bool
            switch json["key"] as? String {
            case "cursorHighlight": s.cursorHighlight = on ?? !s.cursorHighlight
            case "clickRipples":    s.clickRipples    = on ?? !s.clickRipples
            case "keystrokes":      s.keystrokes      = on ?? !s.keystrokes
            case "shortcutsOnly":   s.shortcutsOnly   = on ?? !s.shortcutsOnly
            case "clicksInHUD":     s.clicksInHUD     = on ?? !s.clicksInHUD
            default: return ["error": "unknown key"]
            }

        case "/choose":
            let value = json["value"] as? String
            let step = (json["step"] as? NSNumber)?.intValue ?? 1
            switch json["key"] as? String {
            case "cursorSize":
                s.cursorSize = value.flatMap(CursorSize.init(rawValue:)) ?? Self.cycle(s.cursorSize, by: step)
            case "highlightColor":
                s.highlightColor = value.flatMap(HighlightColor.init(rawValue:)) ?? Self.cycle(s.highlightColor, by: step)
            case "hudPosition":
                s.hudPosition = value.flatMap(HUDPosition.init(rawValue:)) ?? Self.cycle(s.hudPosition, by: step)
            case "hudSize":
                s.hudSize = value.flatMap(HUDSize.init(rawValue:)) ?? Self.cycle(s.hudSize, by: step)
            default: return ["error": "unknown key"]
            }

        case "/message":
            let text = (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let seconds = (json["seconds"] as? NSNumber)?.doubleValue ?? 2.5
            if !text.isEmpty { app.showMessage(text, seconds: seconds) }

        default:
            return ["error": "unknown route \(route)"]
        }
        return state()
    }

    private static func cycle<T: CaseIterable & Equatable>(_ current: T, by step: Int) -> T where T.AllCases.Index == Int {
        let all = Array(T.allCases)
        let i = all.firstIndex(of: current) ?? 0
        let n = all.count
        return all[((i + step) % n + n) % n]
    }

    private func state() -> [String: Any] {
        let s = Settings.shared
        return [
            "running": true,
            "paused": app.isPaused,
            "trusted": app.isTrusted,
            "cursorHighlight": s.cursorHighlight,
            "clickRipples": s.clickRipples,
            "keystrokes": s.keystrokes,
            "shortcutsOnly": s.shortcutsOnly,
            "clicksInHUD": s.clicksInHUD,
            "cursorSize": s.cursorSize.rawValue,
            "highlightColor": s.highlightColor.rawValue,
            "highlightHex": s.highlightColor.hex,
            "hudPosition": s.hudPosition.rawValue,
            "hudSize": s.hudSize.rawValue,
            "options": [
                "cursorSize": CursorSize.allCases.map(\.rawValue),
                "highlightColor": HighlightColor.allCases.map(\.rawValue),
                "hudPosition": HUDPosition.allCases.map(\.rawValue),
                "hudSize": HUDSize.allCases.map(\.rawValue),
            ],
        ]
    }
}

extension HighlightColor {
    var hex: String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
