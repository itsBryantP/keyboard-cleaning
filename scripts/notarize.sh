#!/usr/bin/env bash
#
# notarize.sh — submit a DMG (or zipped app) to Apple notarization and staple
# the ticket (BUILD-3). Only run on a real release with valid credentials.
#
# Usage: scripts/notarize.sh <path-to-dmg-or-zip>
#
# Credentials, either:
#   NOTARY_PROFILE   a notarytool keychain profile name, created once via:
#                      xcrun notarytool store-credentials <name> \
#                        --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>
# or:
#   APPLE_ID, TEAM_ID, APP_PASSWORD   (app-specific password)
set -euo pipefail

TARGET="${1:?Usage: notarize.sh <path-to-dmg-or-zip>}"
[[ -e "$TARGET" ]] || { echo "error: $TARGET not found"; exit 1; }

echo "==> Submitting $TARGET to notarization (this waits for Apple)…"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$TARGET" --keychain-profile "$NOTARY_PROFILE" --wait
else
  : "${APPLE_ID:?Set NOTARY_PROFILE, or APPLE_ID/TEAM_ID/APP_PASSWORD}"
  : "${TEAM_ID:?Set TEAM_ID}"
  : "${APP_PASSWORD:?Set APP_PASSWORD (app-specific password)}"
  xcrun notarytool submit "$TARGET" \
    --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
fi

echo "==> Stapling ticket…"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "==> Done: $TARGET is notarized + stapled."
