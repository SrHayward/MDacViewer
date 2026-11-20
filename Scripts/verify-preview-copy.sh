#!/bin/bash
# Automated verification for plain-text copying from the preview.
#
# Compiles Scripts/preview-copy-test.swift with the app's
# SchemeHandler/State/WebController sources, then loads the real Web/ app in a
# WKWebView, selects rendered Markdown and dispatches a copy event. It checks
# that the clipboard receives text/plain only — never the styled text/html that
# made Claude paste the grey code-block "box".
#
# Usage:  ./Scripts/verify-preview-copy.sh
# Exits 0 on pass, 1 on failure. Safe to re-run.
# Like the other GUI scripts here, it needs a logged-in Mac desktop session
# (it creates a real, invisible window), so it is a local tool, not a CI job.

set -uo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '%s\n' "$*"; }

say "MDacViewer — preview copy verification"
say "→ Compiling the harness from the current checkout…"
if ! swiftc -o "$TMP/preview-copy-test" \
    Sources/MDacViewer/SchemeHandler.swift \
    Sources/MDacViewer/State.swift \
    Sources/MDacViewer/WebController.swift \
    Scripts/preview-copy-test.swift 2>"$TMP/compile.log"; then
  say "  ✘ the harness did not compile"
  sed 's/^/      /' "$TMP/compile.log"
  exit 1
fi

say "→ Running the WebKit checks…"
say

"$TMP/preview-copy-test"
status=$?

say
if [ "$status" -eq 0 ]; then
  say "RESULT: PASS"
  exit 0
else
  say "RESULT: FAIL — the harness reported failing checks (exit $status)"
  exit 1
fi
