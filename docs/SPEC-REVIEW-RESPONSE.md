# KeyboardLock — Spec Review Response

Disposition of every finding in [SPEC-REVIEW.md](./SPEC-REVIEW.md) against [SPEC.md](./SPEC.md). **All 5 blockers accepted and fixed. All 9 majors resolved (2 with modification); 0 deferred, 0 rejected — REV-7 closed 2026-05-28 by PM accepting Option B (FR-9a amended in PRD).** All 5 minors and 3 nits accepted. One new finding (REV-NEW-1) was surfaced while editing and resolved in the spec.

| Field | Value |
| --- | --- |
| Status | Resolved — ready to implement (REV-7 closed by PM 2026-05-28; 0 open) |
| Date | 2026-05-28 |
| Responder | Senior macOS engineer |
| Spec (now v0.2) | [docs/SPEC.md](./SPEC.md) |
| Review | [docs/SPEC-REVIEW.md](./SPEC-REVIEW.md) |
| PRD baseline | [docs/PRD.md](./PRD.md) |

---

## Disposition table

| ID | Severity | Disposition | Spec sections touched | Rationale (1–3 sentences) | Follow-up |
| --- | --- | --- | --- | --- | --- |
| REV-1 | Blocker | **Accept** | ARCH-2, ARCH-3 (diagram), ARCH-4, ARCH-5, EDGE-1, TEST-U5 | Mutating a `@Published`/`@MainActor` property off-main is a real Swift Concurrency violation that traps or corrupts. Split into a thread-safe `LockEnforcement` (enforcement facts, any thread) and a main-only `@Published` UI mirror; the watchdog touches only `LockEnforcement`. | none |
| REV-2 | Blocker | **Accept-with-modification** | UI-5 | The plain menu "Unlock Keyboard" item defeats FR-7's accidental-unlock safeguard — correct. Rather than *remove* the item (reviewer option a, which drops it from the FR-13-enumerated menu), the item is kept but **routes to / focuses the floating panel's HoldButton** so the FR-7 hold is still required. This satisfies both FR-13 (item present) and FR-7 (no bypass). | PM (optional FR-13 wording) |
| REV-3 | Blocker | **Accept** | FSM-1 (new S5 `unlockingDrain`), FSM-2, FSM-3, FSM-4, UI-7, TEST-I2 | The v0.1 tail-of-chord handling was internally contradictory (tap torn down yet "swallows keyUp for 500 ms"). Added `unlockingDrain`: keep the tap installed and dropping ALL events for ~250 ms after a matched hotkey, then tear down. | none |
| REV-4 | Blocker | **Accept** | §1 intro table, BUILD-4, BUILD-5, SPEC-Q4 | Sparkle (third-party + recurring network) cannot coexist with PRD §6.5 "no network calls in v1" and the "no deps" claim. v1 ships a mouse-driven "Check for Updates…" that opens GitHub Releases in the browser (zero app-originated network); Sparkle deferred to v1.1 behind a PRD amendment. | PM (only if v1 background updates wanted) |
| REV-5 | Blocker | **Accept** | EDGE-1 (injection seam + DEBUG stall harness), TEST-U5, TEST-M6 | `lldb process interrupt` halts all threads and lets `ContinuousClock` advance across the pause, so the test passed for the wrong reason. Added a `Clock`/heartbeat injection seam (same code in prod and TEST-U5) and a DEBUG "stall main 6 s" busy-loop for TEST-M6. | none |
| REV-6 | Major | **Accept** | TAP-3, TAP-5, UI-3 ("Re-arming…" pill), UI-7 | Unbounded re-arm gap is unacceptable for a safety app. Re-enable synchronously on the tap thread in the same callback (tightest possible loop), keep the hot path allocation-free, show a "Re-arming…" pill, and bound failures to a transition to `unlockedReady`. | none |
| REV-7 | Major | **Accept (PM closed 2026-05-28, Option B)** | TAP-8, traceability FR-9a, PRD FR-9a | Finding is correct: the `kCGHIDEventTap` consumes ⌥⌘Esc, and allowing it through would have violated FR-6's blanket-suppression contract. PM accepted **Option B**: amend PRD FR-9a to document ⌥⌘Esc as NOT reachable while locked. Matcher has no special-case allowlist; UI-9 / first-run explainer state the limit honestly. No code path remains gated on this decision. | none |
| REV-8 | Major | **Accept-with-modification** | FSM-5, UI-3, SPEC-A2 | Committed to `HoldButton` as an `NSControl`; removed the "fall back to SwiftUI" hedge; defined cursor-exit = cancel (8 pt hysteresis). Modification: reviewer suggested `CADisplayLink`, which is macOS 14+; given the 13.0 floor we specify `CVDisplayLink` or a `DispatchSourceTimer` at ~60 Hz instead. | none |
| REV-9 | Major | **Accept** | TAP-6, DATA-1 | The producer→consumer wiring was ambiguous. Specified: `PreferencesStore.$unlockHotkey` (Combine) → `LockController` subscription on a serial queue → gated by the unlocked-state invariant → write through `LockEnforcement`'s `OSAllocatedUnfairLock`. One direction only. | none |
| REV-10 | Major | **Accept** | PERM-4, FSM-1 (S1 variant), ARCH-1 | "Accessibility granted but tap creation fails until relaunch" is a real macOS behavior. Added a throwaway tap-creation probe after the silent check; on failure, show a "Restart to finish setup" variant with a "Restart Now" button that relaunches and terminates. | none |
| REV-11 | Major | **Accept-with-modification** | EDGE-1, UI-5, ARCH-3 (diagram) | Correct that the panel must not lie after a forced unlock. **Pushed back** on the reviewer's claim that `orderOut`/`close` are background-thread-safe — AppKit is main-thread-only. Instead: watchdog flips a `LockEnforcement` atomic + posts a notification; the panel is dismissed and the icon flipped on the *main* thread when it next runs; honest bound stated for a permanent hang. | none |
| REV-12 | Major | **Accept** | TAP-4, UI-8 | Including `.maskSecondaryFn` in the comparison would make a resting fn/globe key silently no-op the unlock. Excluded fn from both the matcher's `CHORD_MASK` and the recorder (option a). fn is still suppressed as a keystroke (FR-5); it just can't be part of the unlock chord. | none |
| REV-13 | Major | **Accept** | TEST-I1, TEST-I2 | `.cgSessionEventTap` posts *above* `kCGHIDEventTap`, so prod code never saw the events. Switched the inject point to `.cghidEventTap` with a downstream `.cgSessionEventTap` listener to confirm drop; documented the test-runner Accessibility prerequisite (local-only). | none |
| REV-14 | Major | **Accept** | UI-5, SPEC-PRDGAP2 | Cannot ship the ambiguity. Decided in-spec: when the menu bar item is hidden, the always-on-top floating panel carries the full locked-state contract; hiding the item is accepted in writing as subtractive of the FR-15 pulse only. | PM (optional FR-13 wording) |
| REV-15 | Minor | **Accept** | DATA-1 | `prefs.hasCompletedFirstRun` was declared but never read (first-run is permission-driven). Deleted to prevent drift. | none |
| REV-16 | Minor | **Accept-with-modification** | UI-6 | Kept the segmented control (Off/1/3/5 — a superset of the PRD checkbox and the better design) and documented it as a deliberate deviation rather than silently aligning down to a checkbox. PRD edit to FR-2 requested. | PM (FR-2 wording) |
| REV-17 | Minor | **Accept** | UI-3, SPEC-A2 | Non-activating panel + HoldButton mouse routing is the riskiest UI interaction; made it a required up-front prototype with a defined `NSWindow`-floating fallback, replacing SPEC-A2's open-endedness. | none |
| REV-18 | Minor | **Accept** | ARCH-1, SPEC-Q1 | Single-instance enforced via `runningApplications` check + terminate-self, preventing duelling taps from `open -n`. | none |
| REV-19 | Minor | **Accept** | EDGE-2 | `willSleepNotification`'s ~1 s window isn't a contract; added a `didWakeNotification` defensive recheck that forces `unlockedReady` + tears down any surviving tap regardless. | none |
| REV-20 | Minor | **Accept** | UI-4, UI-7 | Replaced the weak green→amber gradient with a distinct system-blue ring + "Locking in N…" headline so the transitional state reads as neither locked nor unlocked (FR-10). | none |
| REV-21 | Nit | **Accept** | §1 intro table | Resolved by REV-4 — table now reads "None in v1," no Sparkle. | none |
| REV-22 | Nit | **Accept** | TEST-S | Added a menu-bar icon snapshot test at 16/32/64 pt and 1×/2× to confirm the SF Symbol composite stays crisp. | none |
| REV-NEW-1 | Major (new) | **Accept (resolved in spec)** | ARCH-1 | Surfaced while editing: the REV-10 relaunch launches a fresh instance before the old one dies, so the REV-18 single-instance check would make the new instance kill *itself*. Resolved with a short-lived `relaunchHandoffUntil` marker so the old instance always loses the race to die. | none |

---

## PRD amendments requested (PM sign-off — NOT made here)

These touch [docs/PRD.md](./PRD.md), which is the PM's source of truth; the spec does not edit it unilaterally.

- **FR-9a / FR-6 conflict (REV-7) — CLOSED 2026-05-28.** PM accepted **Option B**: PRD FR-9a was amended to document ⌥⌘Esc as NOT reachable while locked, preserving FR-6's blanket-suppression contract. The mouse-driven Apple-menu Force Quit (FR-9) remains the supported fallback. PRD edit applied; SPEC TAP-8 + traceability updated; matcher unchanged (no special-case allowlist). No further action.
- **FR-2 wording (REV-16).** Proposed: replace "skippable via a checkbox" with "configurable via a **Pre-lock countdown** control offering Off / 1 s / 3 s / 5 s (default 3 s)." Reflects the implemented superset; no behavioral regression (Off + 3 s reproduce the original two states).
- **FR-13 wording (REV-14).** Proposed: append to FR-13 "…**when the menu bar item is enabled.** If the user disables the menu bar item in Preferences, the locked-state visual contract is carried by the always-on-top floating panel; disabling the item forgoes the FR-15 pulse indicator." Aligns the "at all times" phrasing with the §5.7 toggle.
- **§6.5 / auto-update (REV-4) — confirm, likely no change.** The spec now complies with "no network calls in v1" by deferring Sparkle. A PRD amendment is needed **only if** PM wants background auto-update *in v1*; in that case amend §6.5 to permit the appcast fetch. Otherwise no PRD change is required.
- **§6.5 telemetry (carried forward from SPEC-PRDGAP1).** §6.5 says both "no telemetry beyond crash reports" and "recommended: none in v1." Spec treats **"none in v1" as binding** (no Sentry, no crash-reporter dep). Please confirm so the privacy copy in the first-run explainer is accurate.

---

## Newly opened spec questions

- **NQ-1. `IOPMAssertionRelease` off-main thread-safety.** EDGE-1 has the watchdog release the IOPM assertion from its background queue (handle stored in `LockEnforcement`). SPEC-A5 covers `CGEventTapEnable`/`CFRunLoopSourceInvalidate` as documented thread-safe, but the IOPM release path should be confirmed equally safe (or wrapped) before relying on it during a main-thread hang.
- **NQ-2. 60 Hz hold-progress driver on macOS 13.** `CADisplayLink` is macOS 14+, so REV-8 specifies `CVDisplayLink` *or* a `DispatchSourceTimer`. The final choice (and whether `CVDisplayLink` is worth the wiring vs. a timer) should be settled during the mandatory UI-3 prototype and recorded in code.
- **NQ-3. Integration tests need a granted test runner.** TEST-I1/I2 now post at `.cghidEventTap`, which requires the test process to hold Accessibility + Input Monitoring. These can never run in CI; a documented local setup (grant once, `INTEGRATION_TESTS=1`) is needed, and someone owns running them on the release checklist.
- **NQ-4. Relaunch handoff marker (REV-NEW-1) validation.** The `relaunchHandoffUntil` marker resolves the single-instance/relaunch race on paper; the timing window (3 s) and the `isTerminated` check should be validated against real macOS relaunch latency during implementation.

---

## Ready-to-implement assertion

**All blockers and majors resolved. REV-7 closed 2026-05-28 by PM (Option B; PRD FR-9a amended). The spec is ready to implement with zero gating decisions outstanding.**
