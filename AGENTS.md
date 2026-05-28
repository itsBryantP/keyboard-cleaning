# AGENTS.md

> **Sync note.** This file and `CLAUDE.md` are kept in sync — same content under two filenames so different AI coding tools (Claude Code reads `CLAUDE.md`; Cursor, Codex, Aider, Jules, and others read `AGENTS.md`) pick up the same guidance. **If you edit one, mirror the change to the other in the same commit.** A CI check or a pre-commit hook to enforce this is welcome but not yet in place.

This file provides guidance to AI coding agents when working with code in this repository.

## Repository status

This repo currently contains **design artifacts only** — no source code, no build system, no tests. The Xcode project has not been created yet. There are no build / lint / test commands to run.

The four documents in `docs/` form an intentional chain:

| File | Role | Treat as |
| --- | --- | --- |
| `docs/PRD.md` | Product requirements (PM) | Source of truth for **what** and **why**. Do not edit without an explicit PM-amendment ask. |
| `docs/SPEC.md` | Technical specification (eng) | Source of truth for **how**. Edit when a design decision changes. |
| `docs/SPEC-REVIEW.md` | Skeptical pre-implementation review | Historical record of issues raised. Do not edit — append a new review file if a fresh pass is needed. |
| `docs/SPEC-REVIEW-RESPONSE.md` | Disposition log for the review | Edit when a review finding's status changes (e.g., PM closes a deferred decision). |

When asked to change behavior, first identify which document owns the decision (product = PRD, implementation = SPEC) and edit there before touching code.

## Stable ID conventions

The documents cross-reference each other via stable IDs. Preserve them — they are cited in commits, issues, and the SPEC's traceability table (§12).

- **PRD:** `FR-N` (functional), `AX-N` (accessibility), `L-N` (honest limits), `EC-N` (edge cases), `D-N` (resolved decisions), `SM-N` (success metrics), `F-N` (future work), `G-N` / `NG-N` (goals / non-goals), `UC-N` (use cases).
- **SPEC:** `ARCH-N`, `FSM-N`, `TAP-N`, `PERM-N`, `UI-N`, `EDGE-N`, `DATA-N`, `TEST-N` (U/I/S/M/C variants), `BUILD-N`, `SPEC-A-N` (assumptions), `SPEC-Q-N` (open questions), `SPEC-PRDGAP-N` (PRD ambiguities).
- **Review:** `REV-N`, `REV-NEW-N`.

Add new IDs (monotonic, never renumber). Renumbering breaks traceability silently.

## Product invariants any future code must honor

These are load-bearing safety and product claims from the PRD/SPEC. They are easy to break accidentally during implementation.

- **Mouse-only contract (PRD §5.1, FR-1, FR-7).** Every primary path must be operable without the keyboard, because the keyboard is locked during use. Keyboard shortcuts may exist as accelerators only.
- **Blanket keystroke suppression (FR-3, FR-5, FR-6).** Only ONE chord — the user-configured unlock hotkey (default ⌃⌥⌘L) — passes through the tap. There is **no special-case allowlist for ⌥⌘Esc**: PM closed REV-7 with Option B, so FR-9a is amended to document ⌥⌘Esc as not reachable while locked. The mouse-driven Apple-menu Force Quit (FR-9) is the only keyboard-independent escape.
- **Accidental-unlock safeguard (FR-7, REV-2).** Mouse unlock requires hold-to-unlock (1.5 s) or double-click. A plain single-click unlock is forbidden anywhere in the UI — including the menu bar's "Unlock Keyboard" item, which must route to the floating panel's `HoldButton`, not unlock directly.
- **In-process watchdog only (FR-9c, D-3).** No XPC helper, no separate process. The watchdog mutates only the thread-safe `LockEnforcement` store; it must never write `@Published` / `@MainActor` state directly (REV-1, REV-11).
- **State never persists across launches (DATA-2).** Every launch starts in `unlockedReady`. Booting into a locked state after a crash is a foot-gun.
- **Permissions-gated locking (FR-4, FR-18).** Never show a "locked" UI without an installed event tap. A probe `CGEvent.tapCreate` after permission grant is required (REV-10).
- **No network calls in v1 (PRD §6.5, REV-4).** No analytics, no telemetry, no Sparkle — manual mouse-driven "Check for Updates…" only. This is load-bearing for the first-run permission explainer's privacy copy.

## Expected implementation stack (per SPEC)

When source code is added, it will be:

- **Language / UI:** Swift 5.10+, SwiftUI for window content, AppKit for the menu bar item, the floating `NSPanel`, and CGEventTap glue.
- **Target:** macOS 13.0 Ventura+, universal binary (`arm64` + `x86_64`). Xcode 16+.
- **Bundle ID:** `com.itsbryantp.keyboardlock`.
- **Sandbox:** disabled. Hardened Runtime enabled. Cannot ship through the Mac App Store (L-6).
- **Distribution:** GitHub Releases only, as Developer ID-signed and notarized `.dmg` (D-1, BUILD-3, BUILD-4).
- **Third-party deps in v1:** none.

The architecture is specified in `docs/SPEC.md` §2 (component table + Mermaid diagram). Threading rules in ARCH-4 are non-negotiable: UI / `@Published` state mutations on the main thread; tap callback on a dedicated CFRunLoop thread; watchdog on its own serial queue and writes only to `LockEnforcement`.

## Commits

A `.claude/settings.local.json` pre-allows `git add *` and `git commit -m ' *`. Commits should still only be made when the user explicitly asks. Co-author trailer is `Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
