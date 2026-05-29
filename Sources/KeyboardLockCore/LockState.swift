import Foundation

/// The UI-facing lock state (FSM-1). This is the `@Published` enum on the
/// `@MainActor LockStateMachine` — mutated only on the main thread (ARCH-4).
/// It is never persisted: every launch starts unlocked (DATA-2).
public enum LockState: Equatable, Sendable {
    /// S0. Permissions granted and the tap-creation probe passed.
    case unlockedReady
    /// S1. Cannot lock — a permission is missing, or granted-but-needs-relaunch
    /// (REV-10). Carries the status so the UI can pick the right variant.
    case unlockedNeedsPermission(PermissionStatus)
    /// S2. Pre-lock countdown; mouse-cancelable.
    case countingDown(remaining: TimeInterval)
    /// S3. Tap installed and dropping; watchdog heartbeating; power asserted.
    case locked
    /// S4. Locked + holding the Unlock control; ring filling (substate of S3).
    case confirmingUnlock(progress: Double)
    /// S5 (REV-3). Hotkey unlock accepted; tap stays installed and dropping for
    /// the ~250 ms drain so the chord tail can't leak.
    case unlockingDrain
    /// S6. Transient tap removal / assertion release (~100 ms).
    case tearingDown

    /// The unlocked family (S0/S1). Mirrored into `LockEnforcement` for the
    /// REV-9 binding-update guard.
    public var isUnlocked: Bool {
        switch self {
        case .unlockedReady, .unlockedNeedsPermission: return true
        default: return false
        }
    }

    /// Locked or any of its substates where the tap is still installed
    /// (S3/S4/S5).
    public var isLockedFamily: Bool {
        switch self {
        case .locked, .confirmingUnlock, .unlockingDrain: return true
        default: return false
        }
    }
}

/// Which unlock confirmation gesture the panel uses (FR-7a / FR-7b, DATA-1).
public enum UnlockMode: String, Sendable, CaseIterable {
    case hold
    case doubleClick
}
