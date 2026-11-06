#!/bin/bash
# Automated verification for the preview text-size feature.
#
# Compiles Scripts/preview-font-size-test.swift with the app's
# SchemeHandler/State/WebController sources, then loads the real Web/ app in a
# WKWebView and checks:
#   · the preview (and its headings) resizes live,
#   · the 6px minimum / 72px maximum are enforced,
#   · the chosen size survives a reload (localStorage),
#   · the native AppState uses the same clamp and persists the value.
#
# Usage:  ./Scripts/verify-preview-font-size.sh
# Exits 0 on pass, 1 on failure. Safe to re-run.
# Like the other GUI scripts here, it needs a logged-in Mac desktop session
# (it creates a real, invisible window), so it is a local tool, not a CI job.

set -uo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '%s\n' "$*"; }

say "MDacViewer — preview text-size verification"
say "→ Compiling the harness from the current checkout…"
if ! swiftc -o "$TMP/preview-font-size-test" \
    Sources/MDacViewer/SchemeHandler.swift \
    Sources/MDacViewer/State.swift \
    Sources/MDacViewer/WebController.swift \
    Scripts/preview-font-size-test.swift 2>"$TMP/compile.log"; then
  say "  ✘ the harness did not compile"
  sed 's/^/      /' "$TMP/compile.log"
  exit 1
fi

say "→ Running the WebKit checks…"
say

"$TMP/preview-font-size-test"
status=$?

say
if [ "$status" -eq 0 ]; then
  say "RESULT: PASS"
  exit 0
else
  say "RESULT: FAIL — the harness reported failing checks (exit $status)"
  exit 1
fi
