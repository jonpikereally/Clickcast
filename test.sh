#!/bin/zsh
# Build the control server into a headless harness and hit every route with tools/test-server.py.
set -e
cd "$(dirname "$0")"
CACHE="${TMPDIR:-/tmp}/clickcast-modcache"
BIN="${TMPDIR:-/tmp}/clickcast-harness"
mkdir -p "$CACHE"
swiftc -module-cache-path "$CACHE" -o "$BIN" tools/harness/main.swift Sources/ClickCast/ControlServer.swift Sources/ClickCast/Settings.swift 2>&1 | grep -v xcrun_db || true
"$BIN" > "${TMPDIR:-/tmp}/clickcast-harness.log" 2>&1 &
PID=$!
sleep 1
python3 tools/test-server.py; STATUS=$?
kill $PID 2>/dev/null || true
echo "--- harness log:"; cat "${TMPDIR:-/tmp}/clickcast-harness.log"
exit $STATUS
