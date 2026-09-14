# ClickCast

Menu bar app for screen recordings: makes the mouse and keyboard shortcuts obvious to viewers.

- **Cursor highlight** — a translucent colored ring follows the pointer, so viewers never lose it.
- **Click ripples** — every click sends out an expanding ring (yellow = left, blue = right, green = middle). The ring also shrinks while the button is held, so drags are visible.
- **Keystroke display** — a dark pill at the bottom of the screen shows shortcuts as you press them (`⇧⌘S`, `⌥←`, `esc`), held modifiers (dimmed, so "hold ⌘ then click" reads clearly), repeats (`⌘Z ×3`), and notable clicks (`Right Click`, `⌘ Click`, `Double Click`).

Everything is drawn in click-through overlay windows above every app, including full-screen ones, and is captured by any *display* recording (QuickTime, OBS display capture, ScreenFlow, Cleanshot). Window-only captures of a single app will not include it.

## Install

Build (or rebuild after editing) from this folder:

```bash
./build.sh
```

Then install and launch. Run this in **Terminal.app** (apps can't run from inside the Dropbox folder):

```bash
"$HOME/Library/CloudStorage/Dropbox/Jons Synced Dropbox Folder/For Claude/ClickCast/install.sh"
```

This also installs the Stream Deck plugin (see below) if Stream Deck is present.

macOS will ask for **Accessibility** permission. That's required to see keystrokes; the cursor ring and click ripples work without it. If keystrokes still don't appear after granting, quit and relaunch ClickCast once.

## Use

Click the cursor icon in the menu bar:

| Item | What it does |
|---|---|
| Pause / Resume (`⌃⌥⌘K`) | Hide everything instantly without quitting. Works from any app. |
| Highlight Cursor | Ring that follows the pointer. |
| Click Ripples | Expanding ring on each click. |
| Show Keystrokes | The keystroke pill. |
| Keystroke Display ▸ Shortcuts Only / Everything I Type | Shortcuts Only shows chords with ⌘ ⌃ ⌥ plus special keys (Return, Tab, arrows, Esc, Delete, F-keys). Everything I Type also streams plain typing. |
| Keystroke Display ▸ Show Clicks | Right / middle / modified / double clicks appear in the pill. |
| Keystroke Display ▸ position & text size | Six screen positions; small / medium / large text. |
| Cursor Size, Highlight Color | Ring size (small → huge) and color. |
| Launch at Login | Registers with macOS login items. |

The pill appears on whichever screen the mouse is on. Secure text fields (passwords) are never shown; macOS blocks global key monitoring while they have focus.

## Stream Deck

The plugin lives in its own repo, [clickcast-streamdeck](https://github.com/jonpikereally/clickcast-streamdeck); clone it into `streamdeck/` inside this folder and `install.sh` picks it up. It adds a **ClickCast** category to Stream Deck. The keys mirror the app's live state (they poll it once a second) and show "no app" when ClickCast isn't running; pressing any key then launches it.

| Action | Key | Dial |
|---|---|---|
| Pause / Resume | Lit while the overlay is showing. Toggle, or force pause / resume. | |
| Cursor Highlight, Click Ripples, Keystrokes | Lit while that layer is on. Toggle, or force on / off. | |
| Keystroke Mode | Shortcuts only ↔ everything you type. | |
| Size | Cycle or jump to a cursor ring size, or the keystroke text size. | Rotate to step, press to reset to Medium. |
| Highlight Colour | Cycle or jump to a colour. The key shows the colour. | |
| Keystroke Position | Cycle or jump to one of the six positions. | |
| Show Message | Flash your own text in the pill for N seconds ("Watch this", a chapter title). | |

The plugin talks to the app over a loopback-only HTTP server on `127.0.0.1:8766` (`ControlServer.swift`). Anything else can drive it the same way:

```bash
curl -s -X POST -d '{"toggle":true}' http://127.0.0.1:8766/pause
```

Routes: `GET /state`; `POST /pause {toggle|paused}`; `POST /toggle {key, on?}` for `cursorHighlight`, `clickRipples`, `keystrokes`, `shortcutsOnly`, `clicksInHUD`; `POST /choose {key, value?|step?}` for `cursorSize`, `highlightColor`, `hudPosition`, `hudSize`; `POST /message {text, seconds?}`. Every response is the full state.

## Tests

```bash
./test.sh
```

Compiles the control server into a headless harness and hits every route. `node streamdeck/tools/test-plugin.js` (with the harness or the app running) drives the plugin from a fake Stream Deck and checks the key states it sends back.

## Files

- `Sources/ClickCast/` — Swift sources (AppKit, no Xcode project; built with `swiftc`).
  - `Overlay.swift` — per-screen overlay windows, cursor ring, ripples.
  - `KeystrokeHUD.swift` — the pill, chord/typing/modifier logic.
  - `KeyFormatter.swift` — keycode → symbol mapping (uses the active keyboard layout for unshifted keys).
  - `InputMonitor.swift` — global NSEvent monitors + Accessibility check.
  - `AppDelegate.swift` — menu bar UI and settings.
  - `ControlServer.swift` — loopback HTTP API used by the Stream Deck plugin.
- `streamdeck/` — the Stream Deck plugin (separate repo, see above).
- `tools/make-icon.swift` — regenerates the app icon; `tools/harness/` + `tools/test-server.py` — server tests.
