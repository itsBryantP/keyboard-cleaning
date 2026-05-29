import SwiftUI
import KeyboardLockCore

/// Routes the main window (W1) content by lock state (UI-1, UI-7). The locked
/// family shows a placeholder here; the floating panel (W2) replaces it in
/// Phase 9.
struct RootView: View {
    @ObservedObject var stateMachine: LockStateMachine
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.2), value: stateMachine.state)
    }

    @ViewBuilder private var content: some View {
        switch stateMachine.state {
        case .unlockedReady:
            UnlockedView(hotkey: preferences.unlockHotkey) {
                stateMachine.handle(.lockRequested)
            }
        case .unlockedNeedsPermission:
            PermissionExplainerView(permissions: permissions)
        case let .countingDown(remaining):
            CountdownView(remaining: remaining, total: preferences.countdownSeconds) {
                stateMachine.handle(.cancelCountdown)
            }
        case .locked, .confirmingUnlock, .unlockingDrain, .tearingDown:
            LockedPlaceholderView(hotkey: preferences.unlockHotkey)
        }
    }
}

/// UI-2 — unlocked main window. Green status, large Lock button, hotkey hint.
struct UnlockedView: View {
    let hotkey: HotkeyBinding
    let onLock: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                } else {
                    Image(systemName: "keyboard").font(.system(size: 40))
                }
                Text("KeyboardLock").font(.largeTitle.bold())
            }

            HStack(spacing: 8) {
                Circle().fill(Color(.systemGreen)).frame(width: 12, height: 12)
                Text("Keyboard is active").font(.title3.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Keyboard is active")

            Button(action: onLock) {
                Label("Lock Keyboard", systemImage: "lock.fill")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 200, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            (Text("Locks all keyboard input so you can clean. Unlock with ")
                + Text(hotkey.displayString).font(.system(.callout, design: .monospaced).weight(.bold))
                + Text(" or the on-screen button."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 420, height: 320)
    }
}

/// UI-4 / REV-20 — pre-lock countdown. Distinct system-blue ring + explicit
/// "Locking in N…" headline so the transitional state reads as neither
/// unlocked (green) nor locked (red), satisfying FR-10.
struct CountdownView: View {
    let remaining: TimeInterval
    let total: Int
    let onCancel: () -> Void

    private var secondsLeft: Int { max(0, Int(ceil(remaining))) }
    private var progress: Double {
        guard total > 0 else { return 1 }
        return min(max(1 - remaining / Double(total), 0), 1)
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(.systemBlue), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(secondsLeft)").font(.system(size: 44, weight: .bold, design: .rounded))
            }
            .frame(width: 120, height: 120)

            Text("Locking in \(secondsLeft)…")
                .font(.title2.bold())
                .foregroundStyle(Color(.systemBlue))

            Button("Cancel", action: onCancel)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420, height: 320)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Locking in \(secondsLeft) seconds. Click Cancel to stop.")
    }
}

/// Placeholder shown in W1 while locked. The loud, always-on-top floating panel
/// (UI-3) with the HoldButton replaces this in Phase 9; the hotkey path already
/// unlocks.
struct LockedPlaceholderView: View {
    let hotkey: HotkeyBinding

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Color(.systemRed)).frame(width: 16, height: 16)
                Text("Keyboard is locked — safe to clean").font(.title3.bold())
            }
            Text("Floating unlock panel arrives in the next build. For now, press \(hotkey.displayString) to unlock.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 420, height: 320)
        .background(Color(.systemRed).opacity(0.10))
    }
}
