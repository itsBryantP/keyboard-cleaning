#!/usr/bin/env bash
#
# package-dmg.sh — package KeyboardLock.app into a distributable DMG with an
# /Applications drop target (BUILD-4). Uses hdiutil only — no third-party deps.
#
# Usage: scripts/package-dmg.sh [path-to-KeyboardLock.app]
#   defaults to build/export/KeyboardLock.app
# Output: dist/KeyboardLock-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/export/KeyboardLock.app}"
[[ -d "$APP" ]] || { echo "error: app not found at $APP (run build-release.sh first)"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/KeyboardLock-${VERSION}.dmg"
STAGING="$(mktemp -d)"

echo "==> Staging $APP (v$VERSION)…"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
rm -f "$OUT"

echo "==> Creating ${OUT}"
hdiutil create \
  -volname "KeyboardLock" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$OUT"

rm -rf "$STAGING"
echo "==> Done: $OUT"
echo "    Next: scripts/notarize.sh $OUT"
