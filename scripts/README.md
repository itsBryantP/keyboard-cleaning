# Release scripts

Developer ID signing, notarization, and DMG packaging for KeyboardLock
(BUILD-3, BUILD-4, D-1, L-6). Distribution is GitHub Releases only — there is no
auto-updater in v1 (BUILD-5 / REV-4).

The Xcode project ships **ad-hoc signed (`"-"`)** so it builds locally with no
Apple Team ID in the repo. Release signing is applied by these scripts via
`xcodebuild` overrides. Hardened Runtime is already enabled in the project and
the entitlements (sandbox **off**, HR knobs) are in
`KeyboardLock/KeyboardLock.entitlements`.

## One-time setup

Store a notarytool credential profile in the keychain:

```sh
xcrun notarytool store-credentials KeyboardLockNotary \
  --apple-id "you@example.com" --team-id "ABCDE12345" \
  --password "abcd-efgh-ijkl-mnop"   # app-specific password
```

## Release flow

```sh
export DEVELOPMENT_TEAM=ABCDE12345          # your Apple Developer Team ID
export NOTARY_PROFILE=KeyboardLockNotary

scripts/build-release.sh                     # archive + Developer ID sign + export
scripts/package-dmg.sh                        # -> dist/KeyboardLock-<version>.dmg
scripts/notarize.sh dist/KeyboardLock-*.dmg   # submit + staple
```

Then upload the stapled `.dmg` to the GitHub Release.

> These scripts are intentionally **not** wired into CI or run automatically —
> notarization hits Apple's servers and requires real credentials. Run them by
> hand for a release after the TEST-M smoke checklist (BUILD-6).
