#!/bin/bash
# End-to-end verification for the "editor buffer is no longer persisted" fix.
#
# What it proves, automatically, without anyone looking at the screen:
#
#   1. The new web code is actually running (the once-only `mdac.guide` flag gets
#      written by the new boot() — the old build never wrote it).
#   2. Opening a file no longer persists its text. This is the decisive check:
#      the OLD build wrote the editor contents to localStorage on open (via
#      setText → scheduleSave) and restored it on launch; the fixed build must
#      leave no trace. So we open a file containing a unique sentinel string,
#      quit, and confirm that string is absent from the app's storage.
#   3. The window title is exactly "MDacViewer" with no file open (best-effort:
#      needs Accessibility permission for System Events; skipped if not granted).
#
# It does NOT and cannot check the Save-panel behaviour — that is interactive and
# must be eyeballed (see REPRODUCE.md, steps 7-8).
#
# Usage:  ./Scripts/verify-launch-state.sh
# Always rebuilds the app from this checkout before testing it.
# Exits 0 on pass, 1 on failure. Safe to re-run; cleans up its temp file.

set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.srhayward.mdacviewer"
APP="build/MDacViewer.app"
APP_ABS="$(pwd)/$APP"
TOKEN="MDACVIEWER_SENTINEL_$$_$(date +%s)"
SENTINEL_FILE="$(mktemp -d)/sentinel-$$.md"
BUILD_LOG=""
FAILURES=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✔ %s\n' "$*"; }
bad()  { printf '  ✘ %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
info() { printf '  · %s\n' "$*"; }

cleanup() {
  pkill -x MDacViewer 2>/dev/null || true
  rm -rf "$(dirname "$SENTINEL_FILE")"
  [ -n "$BUILD_LOG" ] && rm -f "$BUILD_LOG"
}
trap cleanup EXIT

# --- locate the app's web storage -------------------------------------------
# A non-sandboxed WKWebView app keeps its localStorage under ~/Library/WebKit;
# a sandboxed one under ~/Library/Containers. Search both, newest first.
storage_files() {
  find "$HOME/Library/WebKit/$BUNDLE_ID" "$HOME/Library/Containers/$BUNDLE_ID" \
       "$HOME/Library/WebKit" -type f \
       \( -name '*.localstorage' -o -name 'localstorage.sqlite*' -o -name '*.sqlite3' \) \
       2>/dev/null | grep -i -E "$BUNDLE_ID|localstorage" || true
}

# Grep binary-safe: sqlite stores keys/values as plain bytes, so strings+fixed
# grep finds them without needing the schema.
storage_contains() {
  local needle="$1" found=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if strings -a "$f" 2>/dev/null | grep -qF -- "$needle"; then found="$f"; break; fi
  done < <(storage_files)
  [ -n "$found" ] && printf '%s' "$found"
}

say "MDacViewer — launch-state verification"
say "bundle id: $BUNDLE_ID"
say

# --- 0. build from the current checkout --------------------------------------
# Always rebuild: a pre-existing bundle may be stale (e.g. built from another
# branch), and testing it would silently verify the wrong code.
say "→ Building from the current checkout (VERSION=0.0.0-verify)…"
BUILD_LOG="$(mktemp -t mdacviewer-build)"
if ! VERSION=0.0.0-verify make app >"$BUILD_LOG" 2>&1; then
  bad "build failed — build output follows"
  sed 's/^/      /' "$BUILD_LOG"
  exit 1
fi
rm -f "$BUILD_LOG"
BUILD_LOG=""
ok "app bundle built"

# --- 1. fresh launch writes the guide flag (proves the new code is running) --
pkill -x MDacViewer 2>/dev/null || true
sleep 1
say
say "→ Launch 1: plain launch, no file (new boot() should write mdac.guide)"
open "$APP_ABS"
sleep 6
pkill -x MDacViewer 2>/dev/null || true
sleep 2

if storage_contains "mdac.guide" >/dev/null; then
  ok "mdac.guide present → the new boot() ran"
else
  bad "mdac.guide NOT found → the new web code did not run (or storage moved)"
  info "storage files searched:"
  storage_files | sed 's/^/      /'
fi

if storage_contains "mdac.content" >/dev/null; then
  info "mdac.content still present — expected on an upgrade (stale key from the old build)."
  info "What matters is that it is never WRITTEN again; the sentinel check below tests that."
else
  ok "mdac.content absent"
fi

# --- 2. the decisive check: opening a file must not persist its text ---------
say
say "→ Launch 2: open a file containing a unique sentinel, then quit"
printf '# Sentinel\n\n%s\n' "$TOKEN" > "$SENTINEL_FILE"
info "sentinel: $TOKEN"
if ! open -a "$APP_ABS" "$SENTINEL_FILE"; then
  bad "could not open the sentinel file with the app (open -a failed)"
fi
sleep 6

# Make sure the file really is the open document — otherwise the storage check
# below would pass vacuously because nothing was ever opened.
OPEN_CONFIRMED=0
if pgrep -x MDacViewer >/dev/null; then
  TITLE2="$(osascript -e 'tell application "System Events" to tell process "MDacViewer" to get value of attribute "AXTitle" of window 1' 2>/dev/null || true)"
  case "$TITLE2" in
    "")
      info "window title unreadable (Accessibility not granted) — cannot confirm the file opened"
      OPEN_CONFIRMED=1
      ;;
    *"$(basename "$SENTINEL_FILE")"*)
      info "file confirmed open in window (\"$TITLE2\")"
      OPEN_CONFIRMED=1
      ;;
    *)
      bad "the sentinel file was not opened (window title: \"$TITLE2\")"
      ;;
  esac
else
  bad "the app is not running after launch 2 — the sentinel file was never opened"
fi
pkill -x MDacViewer 2>/dev/null || true
sleep 2

if [ "$OPEN_CONFIRMED" = 1 ]; then
  HIT="$(storage_contains "$TOKEN" || true)"
  if [ -n "$HIT" ]; then
    bad "the file's text WAS persisted — the buffer is still being written"
    info "found in: $HIT"
  else
    ok "the opened file's text was not persisted — buffer persistence is gone"
  fi
fi

# --- 3. best-effort window title check --------------------------------------
say
say "→ Launch 3: window title with no file open (needs Accessibility permission)"
open "$APP_ABS"
sleep 6
TITLE="$(osascript -e 'tell application "System Events" to tell process "MDacViewer" to get value of attribute "AXTitle" of window 1' 2>/dev/null || true)"
pkill -x MDacViewer 2>/dev/null || true

if [ -z "$TITLE" ]; then
  info "skipped — System Events could not read the title (Accessibility not granted)."
  info "Check by eye instead: it must read exactly \"MDacViewer\"."
elif [ "$TITLE" = "MDacViewer" ]; then
  ok "window title is exactly \"MDacViewer\""
else
  bad "window title is \"$TITLE\" — expected exactly \"MDacViewer\""
fi

# --- verdict ----------------------------------------------------------------
say
if [ "$FAILURES" -eq 0 ]; then
  say "RESULT: PASS (automatic checks)"
else
  say "RESULT: FAIL — $FAILURES automatic check(s) failed"
fi
say "Still to confirm by eye (interactive, cannot be automated here):"
say "  · opening a file sets the title to \"MDacViewer — <filename>\""
say "  · ⌘S writes straight back to that file with NO save panel"
say "  · after quit + relaunch the editor is empty, and ⌘S then shows a Save panel"
say "    (correct now: no file is open)"
exit "$FAILURES"
