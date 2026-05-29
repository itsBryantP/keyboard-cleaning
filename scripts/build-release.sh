#!/usr/bin/env bash
#
# build-release.sh — archive, Developer ID-sign, and export KeyboardLock.app
# (BUILD-3). Hardened Runtime is already enabled in the project and the
# entitlements (sandbox off, HR knobs) live in KeyboardLock/KeyboardLock.entitlements.
# The .xcodeproj stays ad-hoc-signed ("-") for local dev so no Team ID is baked
# into the repo; this script overrides signing for release builds.
#
# Does NOT notarize (run notarize.sh after packaging).
#
# Required:
#   DEVELOPMENT_TEAM   Apple Developer Team ID (10 chars)
# Optional:
#   SIGN_IDENTITY      signing identity (default: "Developer ID Application")
#   CONFIGURATION      build configuration (default: Release)
#   BUILD_DIR          output dir (default: build)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-build}"
ARCHIVE="$BUILD_DIR/KeyboardLock.xcarchive"

mkdir -p "$BUILD_DIR"

echo "==> Archiving ($CONFIGURATION, universal, Hardened Runtime)…"
xcodebuild \
  -project KeyboardLock.xcodeproj \
  -scheme KeyboardLock \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

echo "==> Writing export options…"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key><string>manual</string>
</dict>
</plist>
PLIST

echo "==> Exporting signed app…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

echo "==> Done: $BUILD_DIR/export/KeyboardLock.app"
echo "    Next: scripts/package-dmg.sh, then scripts/notarize.sh"
