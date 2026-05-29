# KeyboardLock

A small, single-purpose macOS utility that **locks your keyboard so you can clean it** without triggering anything. The mouse keeps working the whole time; you end the lock with a configurable hotkey (default **⌃⌥⌘L**) or an on-screen **hold-to-unlock** control.

> **Status:** Implemented from [`docs/SPEC.md`](docs/SPEC.md) (v0.1.0, pre-release). Builds, unit-tested, and runnable locally. Not yet signed/notarized or published to GitHub Releases.

## Why

Wiping down a keyboard means mashing every key. KeyboardLock installs a system-wide event tap that **drops every keystroke** while active, so cleaning doesn't type, delete, switch apps, or trigger shortcuts — while leaving the mouse and Touch ID untouched.

## Features

- **One-click lock** with an optional 1/3/5 s cancelable countdown.
- **Blanket keystroke suppression** — only your one unlock chord passes through.
- **Three ways out, all keyboard-independent-friendly:** the unlock hotkey, an on-screen hold-to-unlock (1.5 s) or double-click control, and mouse-driven Apple-menu → Force Quit as a last resort.
- **Loud locked state:** floating always-on-top panel (red + amber tint + text + timer) and a pulsing menu-bar icon.
- **Safety watchdog:** an in-process watchdog restores the keyboard even if the main thread hangs — the tap teardown never depends on the UI thread.
- **Honest about permissions:** never shows a "locked" UI unless it can actually lock (a real `CGEventTap` probe must pass first).
- **Private by design:** no network calls, no telemetry, no analytics. "Check for Updates…" just opens the Releases page in your browser.
- **Accessible:** VoiceOver announcements, Reduce-Motion and Increase-Contrast support, large hit targets, Voice/Switch Control-friendly unlock.

## Requirements

- macOS 13.0 Ventura or later (universal: Apple Silicon + Intel)
- Xcode 16+ to build (developed against Xcode 26 / Swift 6 toolchain, Swift 5 language mode)
- **Accessibility** and **Input Monitoring** permissions (granted on first run)

The app is **not sandboxed** (a sandboxed build can't install a HID event tap), so it cannot ship through the Mac App Store — distribution is GitHub Releases only.

## Install

### From a local build (to try it now)

```sh
xcodebuild build -scheme KeyboardLock -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/local
cp -R build/local/Build/Products/Release/KeyboardLock.app /Applications/
open /Applications/KeyboardLock.app
```

This build is **ad-hoc signed**, so Gatekeeper blocks the first launch: right-click the app → **Open** → **Open** (or `xattr -dr com.apple.quarantine /Applications/KeyboardLock.app`). Because ad-hoc signatures change per build, you may need to re-grant permissions after rebuilding.

On first launch the app guides you through granting **Accessibility** and **Input Monitoring**, then offers **Restart Now** if macOS needs a relaunch before the tap can install.

### Signed / notarized release

Maintainers build distributable DMGs with the scripts in [`scripts/`](scripts/) (requires an Apple Developer ID):

```sh
export DEVELOPMENT_TEAM=ABCDE12345
export NOTARY_PROFILE=KeyboardLockNotary   # see scripts/README.md
scripts/build-release.sh
scripts/package-dmg.sh
scripts/notarize.sh dist/KeyboardLock-*.dmg
```

## Using it

1. Click **Lock Keyboard** (or the menu-bar item). After the countdown, the keyboard is locked and a floating panel appears.
2. Clean away — keystrokes do nothing; the mouse still works.
3. Unlock by pressing **⌃⌥⌘L**, or **hold** the on-screen "Hold to Unlock" button for 1.5 s.

> While locked, **⌥⌘Esc (keyboard Force Quit) does not work** — the tap intercepts it. If an app freezes, use the mouse: **Apple menu → Force Quit…** (the in-app "Stuck?" sheet shows the steps). Quitting KeyboardLock, sleeping, or locking the screen also restores the keyboard immediately.

## Build & test

```sh
# Core logic unit tests (fast, no UI, no permissions) — run in CI
swift test

# App build
xcodebuild build -scheme KeyboardLock -destination 'platform=macOS'

# Hosted tests (snapshot / accessibility / power)
xcodebuild test -scheme KeyboardLock -destination 'platform=macOS'

# Event-tap integration tests (local only; need granted permissions)
INTEGRATION_TESTS=1 xcodebuild test -scheme KeyboardLock -destination 'platform=macOS' \
  -only-testing:KeyboardLockTests/LockControllerIntegrationTests
```

## Project structure

```
Package.swift                 SwiftPM manifest for the core library
Sources/KeyboardLockCore/     Pure, UI-free logic (state machine, hotkey matcher,
                              LockEnforcement, watchdog, preferences, policies)
Tests/KeyboardLockCoreTests/  swift-test unit suites (TEST-U*)
KeyboardLock.xcodeproj        App project (file-system-synchronized groups)
KeyboardLock/                 App target: SwiftUI/AppKit UI, CGEventTap glue,
                              menu bar, panel, permissions, power, observers
KeyboardLockTests/            Hosted tests (snapshot, AX, power, integration)
scripts/                      Developer ID signing, DMG, notarization
docs/                         PRD, SPEC, and the design review chain
```

The non-UI logic lives in the **`KeyboardLockCore`** Swift package so it can be unit-tested with `swift test` and mocked collaborators; the Xcode app target links it and adds all the AppKit/SwiftUI/IOKit glue.

## Documentation

| Document | Role |
| --- | --- |
| [`docs/PRD.md`](docs/PRD.md) | Product requirements — **what** and **why** |
| [`docs/SPEC.md`](docs/SPEC.md) | Technical specification — **how** |
| [`docs/SPEC-REVIEW.md`](docs/SPEC-REVIEW.md) | Pre-implementation review |
| [`docs/SPEC-REVIEW-RESPONSE.md`](docs/SPEC-REVIEW-RESPONSE.md) | Review disposition log |

Contributor / AI-agent guidance lives in [`AGENTS.md`](AGENTS.md) (mirrored as `CLAUDE.md`).
