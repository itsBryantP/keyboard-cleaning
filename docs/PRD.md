# KeyboardLock — Product Requirements Document

A single-purpose macOS utility that temporarily disables the keyboard so a user can physically clean it without triggering keystrokes, sleeping the Mac, or logging out.

| Field | Value |
| --- | --- |
| Status | Draft v0.1 |
| Last updated | 2026-05-28 |
| Author | TBD (PM placeholder) |
| Engineering owner | TBD |
| Design owner | TBD |
| Target platforms | macOS 13 Ventura and later (Apple Silicon + Intel) |

---

## Assumptions

Flagged for reviewer confirmation. If any of these are wrong, several requirements below should be revisited.

- **A1.** The app is distributed exclusively via **GitHub Releases** as a Developer ID-signed and notarized `.dmg` (no Mac App Store). Reliable global event interception requires Accessibility permission and a `CGEventTap`, which the App Store sandbox does not permit. *Confirmed.*
- **A2.** "Cleaning" sessions are short — typically 30 seconds to a few minutes — so we optimize for a fast lock/unlock cycle, not multi-hour lockouts.
- **A3.** It is acceptable that a small number of system-reserved key combinations (e.g., the power button hardware path, force-restart chords, brightness/volume function keys handled at firmware level) may not be suppressible. We will document this honestly rather than promise total interception.
- **A4.** The Mac will remain awake during a lock session (lid open, on AC or battery). We do not need to defeat clamshell sleep.
- **A5.** v1 targets the keyboard only. Trackpad/mouse locking is out of scope (and would conflict with the mouse-driven unlock requirement).
- **A6.** A single user on a single Mac at a time. No multi-user/MDM/enterprise rollout requirements in v1.
- **A7.** No localization in v1 — English only. Strings will be wrapped for future localization.

---

## 1. Overview & Problem Statement

### 1.1 Problem
Cleaning a Mac keyboard — wiping keys, blowing out crumbs, applying a cleaning cloth — inevitably presses keys. Without intervention this produces stray text in the focused app, triggers shortcuts, can dismiss dialogs, or worse (e.g., ⌘Q in a text editor). The usual workarounds are bad:

- **Shut down or log out** — slow, disruptive, loses window state.
- **Sleep / close the lid** — Touch ID or repeated key presses can wake the Mac; closing the lid sleeps external monitors.
- **Lock screen (⌃⌘Q)** — still accepts password attempts and shows failed-login UI; repeated keypresses can lock the account.
- **System Settings → Keyboard** — no toggle exists to disable the keyboard.

### 1.2 Product
KeyboardLock is a tiny mac-native utility whose entire job is to enter a "locked" state in which keystrokes do not reach macOS or any app, and to exit that state safely. The user never needs the keyboard to operate the app — both lock and unlock can be driven by the mouse or trackpad alone.

---

## 2. Goals & Non-Goals

### 2.1 Goals
- **G1.** One-click lock from a clearly visible UI.
- **G2.** Suppress keystrokes from all attached keyboards (built-in + external USB/Bluetooth) for the duration of a lock session.
- **G3.** Provide at least two independent unlock paths (mouse-driven + a single allowed hotkey) plus a documented safety fallback.
- **G4.** Make the locked vs. unlocked state unambiguous at a glance, including from a few feet away (cleaning posture).
- **G5.** Honestly request and explain the macOS permissions needed (Accessibility, Input Monitoring).
- **G6.** Be a deliberately small, single-purpose utility: install, launch, lock, clean, unlock, quit. No accounts, no telemetry beyond crash reports, no settings sync.

### 2.2 Non-Goals (v1)
- **NG1.** Locking the trackpad, mouse, or other HID devices.
- **NG2.** Parental-controls or anti-tamper "kid mode" (a determined user should always be able to recover — see safety fallback).
- **NG3.** Scheduled or automatic lock (e.g., "lock every Friday at 5pm").
- **NG4.** Enterprise management, MDM profiles, or multi-user policy.
- **NG5.** Locking input from remote control software (Screen Sharing, Apple Remote Desktop), which arrives through different code paths.
- **NG6.** Windows/Linux versions.

---

## 3. Target Users & Use Cases

### 3.1 Primary persona
**"Careful Casey"** — a knowledge worker who cleans their MacBook keyboard every 1–2 weeks and has at least once sent a Slack message of `aaaaaaaaaaaaaa` mid-wipe. Comfortable installing apps from a developer's website; willing to grant Accessibility permission once if the prompt explains why.

### 3.2 Secondary personas
- **IT-adjacent users** wiping down shared/loaner machines between users.
- **Parents/pet owners** who want the keyboard inert for ~60 seconds while a toddler or cat is on the desk. (We do NOT market this as a child-lock — see NG2 — but it is a real use case.)

### 3.3 Top use cases
- **UC-1.** "I want to wipe down my keyboard for 1–2 minutes without typing garbage into my open document."
- **UC-2.** "I want to use compressed air or a vacuum on the keys without invoking shortcuts."
- **UC-3.** "I want to clean while my Mac stays awake on an external display so I don't lose my Zoom call audio or break Time Machine."
- **UC-4.** "My cat is walking on the keyboard. I need 30 seconds of inert keys, then back to normal."

---

## 4. Functional Requirements

Requirements have stable IDs for reference in commits, issues, and tests.

### 4.1 Locking
- **FR-1.** The app SHALL provide a primary **Lock Keyboard** action available as a single mouse click from the main window.
- **FR-2.** The app SHALL provide an optional brief countdown (default 3 seconds, mouse-cancelable) before entering the locked state, so the user has time to set the mouse down and pick up cleaning supplies. The countdown SHALL be skippable via a checkbox stored in app preferences ("Lock immediately, no countdown").
- **FR-3.** Once locked, the app SHALL intercept and discard key-down, key-up, and key-repeat events from all attached keyboards via a system-wide event tap (see §6).
- **FR-4.** The app SHALL NOT enter the locked state if the required permissions (Accessibility, Input Monitoring) have not been granted. Instead it SHALL show an inline explainer and a button that deep-links to the relevant System Settings pane.
- **FR-5.** While locked, modifier keys (⌘, ⌥, ⌃, ⇧, fn) SHALL be suppressed alongside character keys, so chorded shortcuts cannot fire.
- **FR-6.** While locked, the unlock hotkey (see FR-8) SHALL be the only key combination that reaches the app. All other keys SHALL be discarded before reaching the system.

### 4.2 Unlock methods

#### 4.2.1 Mouse-driven unlock (primary)
- **FR-7.** The locked-state UI SHALL display a large, high-contrast **Unlock** control, sized to be easy to hit with a cleaning cloth still in hand. To prevent accidental unlocks from a stray click (cat paw, dropped item):
  - **FR-7a.** The default SHALL be **hold-to-unlock**: press and hold the mouse button on the Unlock control for **1.5 seconds**, with a visible progress ring filling during the hold. Releasing early cancels and resets.
  - **FR-7b.** A preference SHALL allow switching to **double-click to unlock** (within 400 ms) for users who prefer it.
  - Rationale: hold-to-unlock is recommended because a single accidental press is the most likely failure mode (cleaning cloth dragging across the trackpad). See §7.

#### 4.2.2 Hotkey unlock (secondary)
- **FR-8.** The app SHALL allow one configurable **unlock hotkey** that bypasses the lock. Default: **⌃⌥⌘L** (Control + Option + Command + L) — a 3-modifier chord chosen because it is unlikely to be hit by a cleaning cloth or stray finger.
- **FR-8a.** The hotkey SHALL be configurable through the app's preferences while the keyboard is unlocked (i.e., not during a lock session).
- **FR-8b.** The hotkey SHALL require all configured modifiers and SHALL NOT accept a single-key binding (a single key is too easy to hit during cleaning).
- **FR-8c.** If the user has not configured a hotkey, the default SHALL still be active.

#### 4.2.3 Safety fallback (always available)
- **FR-9.** The app SHALL document and support a guaranteed escape path that does not require the app to be responsive:
  - **Recommendation: macOS hard-quit via mouse.** With the Finder active (click the Desktop), choose **Apple menu → Force Quit…**, select KeyboardLock, click **Force Quit**. The OS terminates the process; the event tap is removed automatically by the kernel; keystrokes resume immediately. The entire flow is mouse-only.
  - **FR-9a.** The macOS-level Force Quit dialog (normally invoked via ⌥⌘Esc) SHALL also be reachable, but because it requires keys we do NOT rely on it as the primary fallback.
  - **FR-9b.** As a last resort, holding the physical power button forces a hardware shutdown. This is documented as a final fallback but is destructive (loses unsaved work) and is NOT a primary recovery path.
  - **FR-9c.** The app SHALL include an **in-process watchdog**: a `dispatch_source` timer on a dedicated background queue (not the main queue) SHALL receive heartbeats from the main thread. If heartbeats stop for >5 seconds, the watchdog SHALL tear down the event tap directly. This prevents a hung UI from leaving the keyboard inert. If the entire process dies, the kernel removes the tap automatically (EC-1), so in-process coverage is sufficient — no separate helper process is needed in v1.

### 4.3 Visual states & status
- **FR-10.** The app SHALL have exactly two operational states: **Unlocked** (default) and **Locked**. Transitional states (countdown, hold-to-unlock progress) SHALL be visually distinct from both.
- **FR-11.** In the **Unlocked** state, the main window SHALL show a green status indicator, the text "Keyboard is active," and a prominent **Lock Keyboard** button.
- **FR-12.** In the **Locked** state, the main window SHALL show a red/amber status indicator, the text "Keyboard is locked — safe to clean," a large **Unlock** control, a countup timer ("Locked for 0:42"), and the configured unlock hotkey displayed as text.
- **FR-13.** A **menu bar item** SHALL reflect state at all times via a distinct icon (e.g., keyboard outline = unlocked; keyboard with a lock badge = locked). Clicking it SHALL reveal a menu with **Lock Keyboard** / **Unlock Keyboard**, **Show Main Window**, **Preferences…**, **Quit KeyboardLock**.
- **FR-14.** While locked, the main window SHALL stay above other windows (floating panel level) so the unlock control cannot be hidden by an unrelated click landing in the background.
- **FR-15.** While locked, the menu bar item SHALL pulse subtly (slow 2 Hz) so the locked state is discoverable even if the main window is occluded on a multi-monitor setup.

### 4.4 Permissions & first-run
- **FR-16.** On first launch, the app SHALL present a one-screen explainer of why Accessibility and Input Monitoring permissions are needed, with a single button to open System Settings to the correct pane.
- **FR-17.** The app SHALL detect permission state at launch and on window focus, and SHALL surface a clear remediation banner if permissions have been revoked.
- **FR-18.** The app SHALL NEVER attempt to lock if permissions are missing (see FR-4). Showing a "locked" state without actual interception would be a safety bug.

---

## 5. UX & Interaction Design

### 5.1 Design principles
1. **Mouse-only is the contract.** Every primary path must be operable without the keyboard. Keyboard shortcuts may exist as accelerators, but the mouse path is canonical.
2. **State is loud.** The locked state should be visible from across the desk. Color, icon, motion, and copy all reinforce it.
3. **Hard to lock accidentally, harder to be trapped.** Locking should require a deliberate click; unlocking should be safe against a single stray click but never require keyboard input.
4. **Honest about limits.** If macOS will not let us intercept a specific key, the UI says so.

### 5.2 Main window — Unlocked state
A compact window (~420×320 px) centered on the active display:

- Top: app icon + "KeyboardLock" wordmark.
- Middle: green dot + bold text **"Keyboard is active"**.
- Center: a single large **Lock Keyboard** button (primary, accent color), at least 200×56 px, with a keyboard-with-lock icon.
- Below the button: small text — "Locks all keyboard input so you can clean. Unlock with **⌃⌥⌘L** or the on-screen button."
- Footer: a small gear icon (Preferences) and a `?` (Help / safety fallback) — both mouse-clickable. No menu bar required to discover these.

### 5.3 Main window — Pre-lock countdown
- Replaces the Lock button with a large circular **"Locking in 3…2…1"** progress ring.
- A **Cancel** button next to it stops the countdown and returns to Unlocked state.

### 5.4 Main window — Locked state
- Background tints amber/red so the state is unmistakable.
- Status: red dot + bold text **"Keyboard is locked — safe to clean"**.
- A live counter: **"Locked for 0:42"** (updates each second).
- The large central control becomes **"Hold to Unlock"** — clicking and holding fills a progress ring around the button over 1.5 s; release before completion resets the ring.
- Secondary line: "Or press **⌃⌥⌘L** on your keyboard."
- A small "?" link opens the **Stuck?** sheet (see 5.5).
- The window is `.floating` (above normal windows) and is draggable by its title bar so it does not block what the user is working on after cleaning resumes.

### 5.5 "Stuck?" sheet
A modal explaining the safety fallback in plain language, with a mouse-clickable button labeled **Open Force Quit (Apple menu)** that walks the user through:
1. Click the Apple menu (top-left of screen).
2. Choose **Force Quit…**.
3. Select **KeyboardLock**, click **Force Quit**.

The sheet includes a static screenshot illustration so it is usable while panicked.

### 5.6 Menu bar item
- Icon-only, monochrome template image so it adapts to light/dark menu bar.
- Tooltip: "Keyboard: Active" or "Keyboard: Locked (1:14)".
- Left click opens a menu (see FR-13). No primary action is hidden behind a keyboard modifier.

### 5.7 Preferences window (mouse-only)
Tabs: **General**, **Unlock**, **About**.

- **General**: launch at login (checkbox); show menu bar icon (checkbox, default on); pre-lock countdown duration (segmented control: Off / 1s / 3s / 5s).
- **Unlock**: unlock-confirmation mode (radio: Hold to unlock 1.5s [default] / Double-click to unlock); unlock hotkey field (click to record; field shows the chord and a Reset to default button).
- **About**: version, link to privacy/help, "Quit KeyboardLock".

### 5.8 Accessibility
- **AX-1.** All controls SHALL have descriptive `accessibilityLabel` values for VoiceOver.
- **AX-2.** All state changes (Unlocked → countdown → Locked → Unlocked) SHALL post a VoiceOver announcement.
- **AX-3.** The locked-state color scheme SHALL NOT rely solely on color: an icon, motion, and text all change.
- **AX-4.** All hit targets SHALL meet a minimum 44×44 pt target (Apple HIG), and the primary Lock/Unlock control SHALL be substantially larger.
- **AX-5.** Respect "Reduce Motion" — the pulsing menu bar icon and progress ring animations SHALL fall back to static state changes.
- **AX-6.** Respect "Increase Contrast" — locked-state background and text SHALL meet WCAG AA contrast in both modes.
- **AX-7.** Full Switch Control / Voice Control support: every action reachable by mouse SHALL also be reachable by these assistive input methods (since users of those technologies are precisely the people who may need a "no keyboard" mode).

---

## 6. Technical Considerations

### 6.1 Interception approach
The recommended approach is a **`CGEventTap` installed at `kCGHIDEventTap`** (the lowest tap point a user-space app can reach), filtering for `kCGEventKeyDown`, `kCGEventKeyUp`, and `kCGEventFlagsChanged`, plus `NSSystemDefined` for media keys where possible.

For each event:
- If the event matches the configured unlock hotkey: pass it to the app (or consume it after triggering unlock) and do NOT forward to other apps.
- Otherwise: return `NULL` from the tap callback to drop the event before any app or the WindowServer sees it.

This is the same mechanism used by Karabiner-Elements, BetterTouchTool, and similar utilities, so the approach is well-trodden.

### 6.2 Required permissions
| Permission | Why | API to check |
| --- | --- | --- |
| Accessibility | Required for `CGEventTap` at `kCGHIDEventTap` to receive (and modify/drop) events from other apps. | `AXIsProcessTrustedWithOptions` |
| Input Monitoring | Required since macOS 10.15 for any process that observes keyboard events globally. | `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` |
| (Optional) Login Items | If the user enables "launch at login". | `SMAppService` (macOS 13+) |

The app SHALL request these explicitly, with copy explaining the cleaning use case. It SHALL NOT request any other permission (camera, network, files) in v1.

### 6.3 Honest limitations
These SHALL be documented in-app on the "Stuck?" / Help sheet so users are not surprised:

- **L-1. Secure input fields.** When the frontmost app calls `EnableSecureEventInput` (password fields in Terminal, login windows, 1Password unlock, etc.), event taps installed by user-space apps are bypassed at the HID level. While Secure Input is active, KeyboardLock cannot intercept those keys. **Mitigation:** before locking, the app SHALL detect Secure Input via `IsSecureEventInputEnabled()` and warn the user with a "Close the password prompt first" message; locking SHALL still proceed but the warning sets expectations.
- **L-2. The macOS login window and lock screen.** Event taps from user-space apps do not run at the login/lock screen, so if the screen locks during a session, the keyboard will become active there. **Mitigation:** while locked, the app SHALL temporarily disable display sleep / screen lock via `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)`, released on unlock or quit.
- **L-3. Hardware-level keys.** The physical power button (long-press → shutdown), Touch ID sensor, and on some Macs the brightness/keyboard-backlight function keys are handled below the event-tap layer. KeyboardLock cannot suppress these. The Help sheet SHALL list them explicitly.
- **L-4. Bluetooth keyboard reconnection.** If a Bluetooth keyboard disconnects and reconnects mid-session, it remains intercepted because the tap is per-event-stream, not per-device. No special handling required, but tested.
- **L-5. Fast User Switching.** Switching users while locked is treated like log-out: the tap belongs to the original user session and stops affecting the new session. This is acceptable behavior.
- **L-6. Sandboxing.** Reliable event-tap installation requires a non-sandboxed app, which precludes Mac App Store distribution. **Distribution is via GitHub Releases only**, as a Developer ID-signed and notarized `.dmg`. Auto-update can be wired through Sparkle pointing at the GitHub Releases appcast feed.

### 6.4 Architecture
A small AppKit/SwiftUI app:
- **MainApp** (SwiftUI window scenes + AppKit `NSStatusItem` for the menu bar).
- **LockController** (singleton): manages tap lifecycle, runs on a dedicated `CFRunLoop` thread.
- **Watchdog** (in-process): a `DispatchSourceTimer` on a dedicated background queue receives heartbeats from the main thread every 1 s while locked. If three consecutive heartbeats are missed (≥5 s), the watchdog tears down the event tap and releases the display-sleep assertion directly from its background queue. If the process dies entirely, the kernel removes the tap automatically (EC-1).

### 6.5 Telemetry & privacy
- No analytics, no network calls in v1, except optional crash reports via a privacy-respecting service (e.g., Sentry self-hosted or none at all — recommended: none in v1).
- No keystroke content is ever read. The event tap inspects modifier+keycode for the unlock hotkey match and otherwise drops events; the app SHALL NOT log key identities.
- Document this clearly in the first-run permission explainer to reduce user reluctance to grant Accessibility.

---

## 7. Unlock Methods Comparison

| Method | Reliability | Discoverability | Accidental-trigger risk | Implementation complexity | Notes |
| --- | --- | --- | --- | --- | --- |
| **Unlock hotkey (⌃⌥⌘L)** | High when permissions are intact; depends on event tap allowing one chord through | Medium — visible as text in the locked UI but new users may not memorize it | **Low** — 3 modifiers + a letter is very unlikely to be hit by a cloth | Medium — match the chord inside the tap callback and consume it | The canonical "I'm done cleaning" path for power users. Required by the spec. |
| **Hold-to-unlock (1.5 s)** | Very high — does not require any keyboard or system permission to fire | High — large labeled button with progress ring | **Very low** — a single click does nothing; requires sustained pressure | Low — pure UI | **Recommended default** mouse path. Best balance of safety and ease. |
| **Double-click to unlock** | Very high | High | **Medium** — a stray double-tap on a trackpad (e.g., cleaning the palm rest) can fire it | Low — pure UI | Offered as a preference for users who dislike hold gestures. |
| **Single-click to unlock** | Very high | High | **High** — one accidental click ends the lock | Trivial | **Not offered.** Fails the "safeguard against accidental unlocks" requirement. |
| **Force Quit (Apple menu) — safety fallback** | Highest — bypasses the app entirely, terminates the process so the kernel reclaims the tap | Medium — surfaced in the in-app "Stuck?" help sheet | N/A (deliberate multi-step user action) | None — uses OS behavior | The guaranteed escape hatch. Mouse-only. Documented prominently. |
| **Watchdog auto-release (5 s app hang)** | High for the hang-recovery case | Invisible by design | N/A (only fires when the app is unresponsive) | Medium — separate helper process or background dispatch source | Belt-and-suspenders for app crashes; users should not need to know it exists. |

**Recommendation.** Ship hold-to-unlock as the default mouse path, ⌃⌥⌘L as the default hotkey, and document Force Quit + the watchdog as the safety net. Single-click unlock is intentionally not offered.

---

## 8. Edge Cases & Safety

- **EC-1. App crash while locked.** If the app process exits, macOS automatically removes its event tap; the keyboard immediately becomes responsive. No user action needed. *Verified in testing by `kill -9`-ing the app during a lock session.*
- **EC-2. App hang (UI unresponsive) while locked.** The watchdog (FR-9c) tears down the tap within ~5 seconds. The user can also Force Quit (FR-9).
- **EC-3. Permissions revoked mid-session.** macOS may invalidate the tap if Accessibility is revoked in System Settings. The app SHALL listen for the `kCGEventTapDisabledByTimeout` and `kCGEventTapDisabledByUserInput` callbacks and either re-enable the tap or, if it cannot, immediately transition to Unlocked state with a banner explaining what happened.
- **EC-4. Display sleep / system sleep.** The app SHALL hold a `kIOPMAssertionTypePreventUserIdleDisplaySleep` assertion while locked (see L-2). It SHALL NOT prevent lid-close sleep — closing the lid is a clear user intent to stop using the Mac and should end the session naturally (the tap dies when the session sleeps; on wake, KeyboardLock SHALL come up Unlocked).
- **EC-5. Multiple displays.** The locked-state window SHALL appear on the display containing the mouse cursor at the moment of locking, and the menu bar item SHALL be visible on whichever display hosts the menu bar (system-defined). The window is movable; position is remembered per display configuration.
- **EC-6. External vs. built-in keyboard.** Both are intercepted identically because the tap operates on the event stream, not per-device. Hot-plugging a USB keyboard mid-session SHALL be handled — newly arriving events go through the same tap and are dropped.
- **EC-7. Bluetooth keyboard low battery / disconnect.** No special handling; the tap continues to suppress whatever arrives. If the BT keyboard disconnects entirely, there is nothing to suppress; on reconnect, suppression resumes.
- **EC-8. Lock screen / login window.** As noted (L-2), event taps do not run there. The display-sleep assertion is the mitigation. If a user manually invokes the lock screen via the Apple menu while KeyboardLock is locked, the app SHALL detect the session-lock notification (`com.apple.screenIsLocked`) and end the lock session (transition to Unlocked) so the user can log back in normally.
- **EC-9. Secure input field active at lock time.** Warn but allow (L-1). On unlock, restore normal behavior.
- **EC-10. Lock invoked twice (double Lock click).** Idempotent — the second click is a no-op while already locked or counting down.
- **EC-11. Unlock hotkey collides with another app's global shortcut.** Because the unlock hotkey is matched inside the tap callback before forwarding, KeyboardLock consumes it first and the other app does not see it during a lock session. Outside a lock session, the hotkey is not registered globally — there is no collision when unlocked.
- **EC-12. Voice Control / Switch Control users.** These input paths arrive through accessibility APIs, not the HID event stream, and are NOT suppressed. This is intentional — these users need a way to unlock too. The mouse-driven Unlock control is reachable via Voice Control ("Click Unlock") and Switch Control scanning.
- **EC-13. Screen Sharing / Remote Desktop.** Out of scope (NG5). Remote input may or may not be suppressed depending on the path; documented as undefined behavior in v1.

---

## 9. Success Metrics

Because the app has no telemetry by default, most metrics are qualitative or measured via opt-in user research.

- **SM-1. Time-to-first-successful-lock.** Median user installs the app, grants permissions, and completes a lock+unlock cycle in **under 90 seconds**. Measured via moderated usability testing (n≥6).
- **SM-2. Accidental unlock rate.** In a 5-minute simulated cleaning session (testers actively wiping the keyboard and trackpad), **fewer than 5%** of sessions end via unintended unlock. Measured via the same usability study.
- **SM-3. Safety fallback comprehension.** **≥80%** of testers, when told "imagine the app froze," successfully execute the Force Quit fallback within 30 seconds using only the mouse, after reading the in-app "Stuck?" sheet once.
- **SM-4. Permission grant rate.** Of users who launch the app for the first time, **≥70%** grant both required permissions on the first try. (Below this threshold, revisit the explainer copy.)
- **SM-5. Crash-free sessions.** **≥99.5%** of lock sessions complete without the watchdog firing. Measured via opt-in crash reporting.
- **SM-6. App Store / forum sentiment.** Net positive reviews; primary failure modes named in negative reviews should be addressable (e.g., permission confusion) rather than fundamental (e.g., "didn't actually block keys").

---

## 10. Future Considerations / Out of Scope

Listed here so reviewers know they were considered and deliberately deferred.

- **F-1. Trackpad / mouse lock mode.** A separate "Surface lock" mode that also suppresses pointer input, with a hardware-only unlock (e.g., long-press a Touch ID sensor). Conflicts with the mouse-driven unlock model and would require a fundamentally different safety story; revisit only if there is demand.
- **F-2. Menu bar quick-toggle.** A single-click "Lock now" item directly in the menu bar (skipping the main window). Easy win for v1.1.
- **F-3. Timed auto-lock.** "Lock for 60 seconds then auto-unlock" — useful for the cat-on-keyboard case (UC-4). Low complexity; consider for v1.1.
- **F-4. Configurable lock duration cap.** A safety setting: "Never stay locked longer than N minutes." Belt-and-suspenders alongside the watchdog.
- **F-5. Multiple hotkey bindings.** Allow more than one unlock hotkey (e.g., for users with split keyboards).
- **F-6. Visual cleaning timer / checklist.** "Wipe keys → blow out crumbs → microfiber" guided overlay. Probably scope creep; deferred.
- **F-7. Trackpad-as-fallback "draw a shape" unlock.** Draw an L-shape on the trackpad to unlock. More fun than useful; deferred.
- **F-8. Localization.** English-only in v1 (A7); add common locales in v1.1+.
- **F-9. Apple Silicon Touch ID unlock.** If accessible from a user-space app, allow a fingerprint tap as a third unlock path. Investigate feasibility for v1.1.
- **F-10. Mac App Store distribution.** Requires a sandbox-compatible interception strategy, which today does not exist for arbitrary key suppression. Revisit if Apple ships a supported API.

---

## Resolved Decisions

The original open questions are settled as follows:

- **D-1 (was OQ-1) — Distribution.** GitHub Releases only, as a Developer ID-signed and notarized `.dmg`. No Mac App Store build. Reflected in A1 and L-6.
- **D-2 (was OQ-2) — Default pre-lock countdown.** **3 seconds**, mouse-cancelable, with a preference to disable. Reflected in FR-2.
- **D-3 (was OQ-3) — Watchdog architecture.** **In-process** `DispatchSourceTimer` on a dedicated background queue. No separate XPC helper in v1; revisit only if real-world hang reports show the in-process timer is insufficient. Reflected in FR-9c and §6.4.
- **D-4 (was OQ-4) — Default unlock hotkey.** **⌃⌥⌘L** as proposed. No known collision with default macOS shortcuts or major apps; user-configurable in Preferences if a conflict arises. Reflected in FR-8.
