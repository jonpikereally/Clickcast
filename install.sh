#!/bin/zsh
# Install ClickCast to ~/Applications (and the Stream Deck plugin), then launch it.
# Run this from Terminal.app: apps can't run from inside the Dropbox folder, and Claude's
# sandbox can't write to ~/Applications or ~/Library.
set -e
cd "$(dirname "$0")"

# --- App ----------------------------------------------------------------------
mkdir -p ~/Applications
pkill -x ClickCast 2>/dev/null || true
sleep 0.5
rm -rf ~/Applications/ClickCast.app
ditto --norsrc ClickCast.app ~/Applications/ClickCast.app
codesign --force --sign - ~/Applications/ClickCast.app
# Ad-hoc signing changes identity on every rebuild; clear the stale Accessibility grant so macOS asks again.
tccutil reset Accessibility com.jonpike.clickcast >/dev/null 2>&1 || true
echo "Installed ~/Applications/ClickCast.app"

# --- Stream Deck plugin ---------------------------------------------------------
PLUGINS="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins"
PLUGIN="com.jonpike.clickcastdeck.sdPlugin"
if [[ -d "$PLUGINS" && -d "streamdeck/$PLUGIN" ]]; then
  if pgrep -xq "Stream Deck"; then
    echo "Quitting Stream Deck to swap the plugin…"
    osascript -e 'quit app "Stream Deck"' || true
    for i in {1..20}; do pgrep -xq "Stream Deck" || break; sleep 0.5; done
  fi
  rm -rf "$PLUGINS/$PLUGIN"
  ditto "streamdeck/$PLUGIN" "$PLUGINS/$PLUGIN"
  echo "Installed $PLUGINS/$PLUGIN"
  open -a "Stream Deck" || echo "Start Stream Deck manually to load the plugin."
else
  echo "Stream Deck (or the streamdeck/ folder) not found — skipped the plugin. Get it from https://github.com/jonpikereally/clickcast-streamdeck"
fi

open ~/Applications/ClickCast.app
echo
echo "ClickCast launched. Grant Accessibility when asked (needed for keystrokes)."
echo "In Stream Deck, the actions are under the “ClickCast” category."
