import os

/// The thread-safe source of truth for the *enforcement* facts — tap installed?
/// IOPM assertion held? locked? current `HotkeyBinding`? — readable and
/// writable from any thread (ARCH-4, DATA-2).
///
/// This is the store the tap thread and the watchdog touch. Crucially it holds
/// NO `@Published` / AppKit state: the watchdog can flip `isLocked`, release the
/// power assertion, and tear the tap down from its background queue without ever
/// hopping to main (REV-1, REV-11). The `@MainActor` UI mirror reconciles
/// against this store when main next runs (EDGE-1).
///
/// All fields sit behind one `OSAllocatedUnfairLock` (macOS 13+). Each accessor
/// takes the lock for a single trivial copy and never nests, so it is
/// effectively atomic and uncontended — the hot path (TAP-6 binding read) and
/// the menu-bar 250 ms `isLocked` read (REV-11) are both single-field copies.
public final class LockEnforcement: @unchecked Sendable {
    private struct State {
        var binding: HotkeyBinding
        var tapInstalled: Bool = false
        var lockedFlag: Bool = false
        /// `IOPMAssertionID` (a `UInt32`); 0 means "no assertion held".
        var iopmAssertionID: UInt32 = 0
        /// REV-6: set while the tap is re-arming after a timeout (drives the
        /// "Re-arming…" pill). Cleared on the next clean pass.
        var rearming: Bool = false
        /// TAP-5: consecutive `tapDisabledByTimeout` events; the controller
        /// gives up if this trips its cap.
        var consecutiveTapTimeouts: Int = 0
        /// REV-9 / TAP-6: thread-safe mirror of "the UI state machine is in the
        /// unlocked family", so the controller's binding-update subscription can
        /// reject a mid-lock binding change off the main thread.
        var unlocked: Bool = true
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(binding: HotkeyBinding = .defaultUnlock) {
        state = OSAllocatedUnfairLock(initialState: State(binding: binding))
    }

    // MARK: - Unlock chord (TAP-6)

    /// Read on every keystroke by the tap thread; written rarely by the main
    /// thread on a preference change while unlocked (REV-9).
    public var binding: HotkeyBinding {
        get { state.withLock { $0.binding } }
        set { state.withLock { $0.binding = newValue } }
    }

    // MARK: - Enforcement flags

    public var tapInstalled: Bool {
        get { state.withLock { $0.tapInstalled } }
        set { state.withLock { $0.tapInstalled = newValue } }
    }

    /// Read by the menu-bar timer (REV-11); set false by the watchdog on
    /// starvation (REV-1).
    public var isLocked: Bool {
        get { state.withLock { $0.lockedFlag } }
        set { state.withLock { $0.lockedFlag = newValue } }
    }

    public var iopmAssertionID: UInt32 {
        get { state.withLock { $0.iopmAssertionID } }
        set { state.withLock { $0.iopmAssertionID = newValue } }
    }

    public var rearming: Bool {
        get { state.withLock { $0.rearming } }
        set { state.withLock { $0.rearming = newValue } }
    }

    public var consecutiveTapTimeouts: Int {
        state.withLock { $0.consecutiveTapTimeouts }
    }

    /// Mirror of `LockStateMachine.isUnlocked` (REV-9). The state machine writes
    /// it on every transition; the controller reads it off-main to gate binding
    /// changes.
    public var isUnlockedMirror: Bool {
        get { state.withLock { $0.unlocked } }
        set { state.withLock { $0.unlocked = newValue } }
    }

    // MARK: - Tap-timeout bookkeeping (TAP-5)

    /// Bumps and returns the consecutive-timeout count in one locked step.
    @discardableResult
    public func recordTapTimeout() -> Int {
        state.withLock {
            $0.consecutiveTapTimeouts += 1
            return $0.consecutiveTapTimeouts
        }
    }

    public func resetTapTimeouts() {
        state.withLock { $0.consecutiveTapTimeouts = 0 }
    }

    // MARK: - Force-stop snapshot (used by the watchdog, EDGE-1)

    /// Atomically clears the locked/tap/rearming flags and the stored assertion
    /// handle, returning the assertion id that was held (0 if none) so the
    /// caller can release it off-main. Resetting all enforcement facts in one
    /// locked step avoids a half-torn-down view.
    @discardableResult
    public func clearForForceStop() -> UInt32 {
        state.withLock {
            let assertion = $0.iopmAssertionID
            $0.lockedFlag = false
            $0.tapInstalled = false
            $0.rearming = false
            $0.iopmAssertionID = 0
            return assertion
        }
    }
}
