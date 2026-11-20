#!/bin/bash
# Automated verification for document tabs and the width-safe preview.
#
# Compiles Scripts/tabs-and-layout-test.swift with the app's
# SchemeHandler/State/WebController sources, then loads the real Web/ app in a
# WKWebView and checks:
#   · each tab keeps its own text, active editor model and dirty state,
#   · switching tabs updates the editor and window title,
#   · closing a tab disposes only that tab's model,
#   · long code lines, URLs and wide tables wrap instead of scrolling
#     sideways (the preview has no horizontal scrollbar),
#   · Editor Only / Split / Preview Only show the right pane(s) and the
#     single-pane modes fill the content area without changing the window.
#
# Usage:  ./Scripts/verify-tabs-and-layout.sh
# Exits 0 on pass, 1 on failure. Safe to re-run.
# Like the other GUI scripts here, it needs a logged-in Mac desktop session
# (it creates a real, invisible window), so it is a local tool, not a CI job.

set -uo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '%s\n' "$*"; }

say "MDacViewer — tabs and preview-layout verification"
say "→ Compiling the harness from the current checkout…"
if ! swiftc -o "$TMP/tabs-and-layout-test" \
    Sources/MDacViewer/SchemeHandler.swift \
    Sources/MDacViewer/State.swift \
    Sources/MDacViewer/WebController.swift \
    Scripts/tabs-and-layout-test.swift 2>"$TMP/compile.log"; then
  say "  ✘ the harness did not compile"
  sed 's/^/      /' "$TMP/compile.log"
  exit 1
fi

say "→ Running the WebKit checks…"
say

"$TMP/tabs-and-layout-test"
status=$?

say
if [ "$status" -eq 0 ]; then
  say "RESULT: PASS"
  exit 0
else
  say "RESULT: FAIL — the harness reported failing checks (exit $status)"
  exit 1
fi
