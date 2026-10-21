#!/bin/bash
# Automated regression test for the red close button crash.
#
# 1.0.2 could not be closed with its red button: the intercepted button action
# called performClose(nil), which simulates a click on that same button, so the
# action re-fired until the main thread's stack overflowed (the crash report
# shows ~10,000 recursive closeButtonPressed frames).
#
# This script compiles the app's window/dirty-tracking code into a small harness
# (Scripts/close-button-test.swift) that clicks the close button in-process and
# checks the window actually closes. No Accessibility permission is needed: the
# process either closes the window (pass) or dies with the same crash (fail).
#
# It also checks the title state machine: an edit with no file open must show
# the unsaved-changes asterisk, and opening a file must clear it.
#
# Usage:  ./Scripts/verify-close-button.sh
# Exits 0 on pass, 1 on failure. Safe to re-run.
# Like the other GUI scripts here, it needs a logged-in Mac desktop session
# (it creates a real window), so it is a local tool, not a CI job.

set -uo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '%s\n' "$*"; }

say "MDacViewer — close-button regression test"
say "→ Compiling the harness from the current checkout (debug)…"
if ! swiftc -o "$TMP/close-button-test" \
    Sources/MDacViewer/WindowFrameSaver.swift \
    Sources/MDacViewer/State.swift \
    Sources/MDacViewer/WebController.swift \
    Scripts/close-button-test.swift 2>"$TMP/compile.log"; then
  say "  ✘ the harness did not compile"
  sed 's/^/      /' "$TMP/compile.log"
  exit 1
fi

say "→ Clicking the red close button in-process…"
say

"$TMP/close-button-test"
status=$?

say
if [ "$status" -eq 0 ]; then
  say "RESULT: PASS"
  exit 0
elif [ "$status" -ge 128 ]; then
  say "RESULT: FAIL — the harness died with signal $((status - 128))"
  say "        (the close button recursed instead of closing the window;"
  say "         a new crash report for close-button-test may have appeared)"
  exit 1
else
  say "RESULT: FAIL — the harness reported failing checks (exit $status)"
  exit 1
fi