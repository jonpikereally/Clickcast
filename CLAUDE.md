# ClickCast — notes for Claude

Native Swift menu bar app (AppKit + Carbon for key layout, ServiceManagement for login item). Same build/deploy pattern as PasteStack:

- Build: `./build.sh` (direct `swiftc`, module cache in `$TMPDIR`). The `xcrun_db` stderr line is harmless sandbox noise.
- Install: the user runs `install.sh` in Terminal.app. It copies to `~/Applications`, re-signs ad-hoc, resets the Accessibility TCC grant (ad-hoc signing changes identity per build), and launches.
- The app cannot run from the Dropbox folder via Finder; running the binary directly from Bash works for a crash smoke test only (Accessibility prompt fails under the sandbox).
- Overlay windows use `CGWindowLevelForKey(.assistiveTechHighWindow)` so they sit above full-screen apps and are captured by display recorders.
- Global key monitors silently never fire without Accessibility; `AppDelegate.checkTrust` polls every 2 s and re-installs them once granted.
- Pause hotkey is hard-coded ⌃⌥⌘K (keyCode 40) in `AppDelegate.wireInput`.
- App icon: `tools/make-icon.swift` renders the PNG set; `iconutil` fails under the sandbox, so the `.icns` is assembled by hand (Python: `icns` header + `icp4/icp5/ic07…ic14` chunks each wrapping a PNG). The finished `AppIcon.icns` is committed inside the bundle, so `build.sh` does not need to regenerate it.
- Control server (`ControlServer.swift`, `127.0.0.1:8766`) is plain BSD sockets + GCD, not Network.framework: under the session sandbox NWListener never reaches `.ready` (no state callback at all), while BSD sockets work. Routes run on the main thread via `DispatchQueue.main.sync`.
- **The app never finishes launching under the sandbox** (no WindowServer session; `applicationDidFinishLaunching` is never called), so "it ran for 4 s without crashing" proves nothing beyond linking. Test the server with `./test.sh` (headless harness, `tools/harness/main.swift` stubs `AppDelegate`) and the plugin with `node streamdeck/tools/test-plugin.js`.
- Stream Deck plugin lives in `streamdeck/com.jonpike.clickcastdeck.sdPlugin`; same shape as the Neewer plugin (`ws` vendored in `bin/node_modules`, no build step, `render-icons.sh` for PNGs). `install.sh` quits Stream Deck, swaps the plugin, and relaunches it. `ditto` is blocked in the sandbox for copies into the project; use `cp -R`.
