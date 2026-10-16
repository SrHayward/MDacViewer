#!/bin/bash
# Downloads the pinned versions of the rendering libraries into Web/vendor/.
# No Node/npm required — fetches tarballs straight from the npm registry.

set -euo pipefail
cd "$(dirname "$0")/.."

MARKED_VER=15.0.7
PURIFY_VER=3.4.13
MERMAID_VER=11.16.1
GHMDCSS_VER=5.8.1
MONACO_VER=0.52.2

VENDOR=Web/vendor
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

get() { # get <package> <version>  → extracts (stripped) into $TMP
  local pkg=$1 ver=$2
  curl -fsSL "https://registry.npmjs.org/${pkg}/-/${pkg}-${ver}.tgz" \
    | tar -xzf - -C "$TMP" --strip-components=1
}

mkdir -p "$VENDOR"

echo "Fetching marked ${MARKED_VER}…"
get marked "$MARKED_VER"
cp "$TMP/marked.min.js" "$VENDOR/marked.min.js"
rm -rf "$TMP"/*

echo "Fetching DOMPurify ${PURIFY_VER}…"
get dompurify "$PURIFY_VER"
cp "$TMP/dist/purify.min.js" "$VENDOR/purify.min.js"
rm -rf "$TMP"/*

echo "Fetching mermaid ${MERMAID_VER}…"
get mermaid "$MERMAID_VER"
cp "$TMP/dist/mermaid.min.js" "$VENDOR/mermaid.min.js"
rm -rf "$TMP"/*

echo "Fetching github-markdown-css ${GHMDCSS_VER}…"
get github-markdown-css "$GHMDCSS_VER"
cp "$TMP/github-markdown-light.css" "$VENDOR/"
rm -rf "$TMP"/*

echo "Fetching dark-dimmed theme (vendored by markdown-live-preview, MIT)…"
curl -fsSL "https://raw.githubusercontent.com/tanabe/markdown-live-preview/main/public/css/github-markdown-dark_dimmed.css" \
  -o "$VENDOR/github-markdown-dark-dimmed.css"

echo "Fetching monaco-editor ${MONACO_VER}…"
get monaco-editor "$MONACO_VER"
mkdir -p "$VENDOR/monaco/min"
cp -R "$TMP/min/vs" "$VENDOR/monaco/min/"
rm -rf "$TMP"/*

echo "Fetching GitHub mark…"
mkdir -p Resources
if curl -fsSL "https://github.githubassets.com/favicons/favicon.png" \
    -o Resources/github-mark.png; then
  :
else
  echo "  (could not fetch GitHub mark — the app will fall back to a generic icon)"
  rm -f Resources/github-mark.png
fi

echo
echo "Vendor contents:"
du -sh "$VENDOR"/* | sort -k2
echo
echo "Done."
