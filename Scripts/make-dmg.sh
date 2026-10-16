#!/bin/bash
# Packages build/MDacViewer.app into dist/MDacViewer-<version>.dmg (drag-to-Applications).
# Usage: VERSION=1.0.0 ./Scripts/make-dmg.sh

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP=build/MDacViewer.app
STAGE=build/dmg-stage
DMG=dist/MDacViewer-$VERSION.dmg

if [ ! -d "$APP" ]; then
  echo "error: $APP not found — run Scripts/build-app.sh first" >&2
  exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" dist

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "MDacViewer" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

echo "Created $DMG"
