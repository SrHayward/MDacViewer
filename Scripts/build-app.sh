#!/bin/bash
# Builds MDacViewer.app into build/.
# Usage: VERSION=1.0.0 ./Scripts/build-app.sh

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP=build/MDacViewer.app

if [ ! -f Resources/AppIcon.icns ]; then
  echo "Generating app icon…"
  swift Scripts/make-icon.swift
fi

if [ ! -f Web/vendor/marked.min.js ]; then
  echo "Vendored libraries missing — running Scripts/fetch-vendor.sh…"
  ./Scripts/fetch-vendor.sh
fi

echo "Building (swift build -c release)…"
BIN_DIR=$(swift build -c release --show-bin-path)
swift build -c release

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/MDacViewer" "$APP/Contents/MacOS/MDacViewer"

sed -e "s/__VERSION__/${VERSION}/g" Resources/Info.plist > "$APP/Contents/Info.plist"

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ -f Resources/github-mark.png ]; then
  cp Resources/github-mark.png "$APP/Contents/Resources/github-mark.png"
fi

mkdir -p "$APP/Contents/Resources/web"
ditto Web "$APP/Contents/Resources/web"

echo "Signing (ad-hoc)…"
codesign --force -s - "$APP"

echo "Built $APP (version $VERSION)"
