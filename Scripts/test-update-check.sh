#!/bin/bash
# End-to-end test for the "update available" indicator — no release required.
#
# What it does:
#   1. builds the app;
#   2. serves a fake GitHub feed ({"tag_name": "99.0.0"}) from a local port;
#   3. points the app at that feed via the `updates.feedURL` test override;
#   4. clears previous update state, launches the app and waits for the check;
#   5. verifies the check ran and the result was persisted.
#
# Expected: an update icon appears in the toolbar (between the Dark mode
# toggle and the GitHub button). Hover it for the "Update available" tooltip;
# clicking it opens the Releases page in the browser.
#
# Notes: quits a running MDacViewer first, and removes the update-state keys
# from com.srhayward.mdacviewer defaults when it exits.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-8975}"
BUNDLE_ID="com.srhayward.mdacviewer"
APP="build/MDacViewer.app"
FEED_DIR="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    { kill "$SERVER_PID"; wait "$SERVER_PID"; } 2>/dev/null || true
  fi
  defaults delete "$BUNDLE_ID" updates.feedURL 2>/dev/null || true
  defaults delete "$BUNDLE_ID" updates.latestVersion 2>/dev/null || true
  defaults delete "$BUNDLE_ID" updates.lastChecked 2>/dev/null || true
  rm -rf "$FEED_DIR"
}
trap cleanup EXIT

echo "→ Building the app (VERSION=${VERSION:-1.0.0})…"
VERSION="${VERSION:-1.0.0}" make app >/dev/null

echo "→ Serving fake feed on http://127.0.0.1:$PORT (tag 99.0.0)…"
echo '{"tag_name": "99.0.0"}' > "$FEED_DIR/release.json"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FEED_DIR" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1

echo "→ Pointing the app at the fake feed and clearing previous state…"
pkill -x MDacViewer 2>/dev/null || true
sleep 1
defaults write "$BUNDLE_ID" updates.feedURL "http://127.0.0.1:$PORT/release.json"
defaults delete "$BUNDLE_ID" updates.latestVersion 2>/dev/null || true
defaults delete "$BUNDLE_ID" updates.lastChecked 2>/dev/null || true

echo "→ Launching the app (the automatic check runs ~5 s after launch)…"
open "$APP"

LATEST=""
for _ in $(seq 1 20); do
  LATEST="$(defaults read "$BUNDLE_ID" updates.latestVersion 2>/dev/null || true)"
  if [ -n "$LATEST" ]; then break; fi
  sleep 1
done
CHECKED="$(defaults read "$BUNDLE_ID" updates.lastChecked 2>/dev/null || echo missing)"

echo
echo "Result:"
echo "  updates.latestVersion = ${LATEST:-missing}"
echo "  updates.lastChecked   = $CHECKED"
echo

if [ "$LATEST" = "99.0.0" ]; then
  echo "✔ Check ran and was persisted."
  echo "  An update icon should be visible in the toolbar now (between the"
  echo "  Dark mode toggle and the GitHub button). Hover → \"Update available\"."
else
  echo "✘ Expected updates.latestVersion = 99.0.0."
  echo "  Is the app running? Did macOS prompt about python3 accepting connections?"
  exit 1
fi
