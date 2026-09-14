// Standalone harness: runs ControlServer against a stub AppDelegate so the HTTP layer and
// routes can be tested without a WindowServer session (the sandbox can't launch AppKit apps).
import Foundation

final class AppDelegate {
    private(set) var isPaused = false
    var isTrusted = true
    var messages: [String] = []
    func setPaused(_ p: Bool) { isPaused = p }
    func showMessage(_ text: String, seconds: Double) { messages.append(text); NSLog("message: \(text) (\(seconds)s)") }
}

enum AppVersion { static let version = "harness" }

let app = AppDelegate()
let server = ControlServer(app: app)
server.start()
RunLoop.main.run()
