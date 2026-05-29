import Foundation
import Combine

// MARK: - Collaborator seams (ARCH-5)

/// The state machine drives the tap through this seam; `LockController`
/// conforms in the app target.
public protocol LockTapControlling: AnyObject {
    var onUnlockHotkey: (() -> Void)? { get set }
    var onTapInterrupted: (() -> Void)? { get set }
    @discardableResult func installTap() -> Bool
    func removeTap()
}

/// `PowerManager` conforms (Phase 7). `endAssertion` must be idempotent so the
/// watchdog-forced path can call it after the watchdog already released.
public protocol PowerAsserting: AnyObject {
    func beginAssertion()
    func endAssertion()
}

/// `Watchdog` conforms (Phase 6).
public protocol LockWatchdogControlling: AnyObject {
    func start()
    func stop()
    func heartbeat()
}

/// `PreferencesStore` conforms (Phase 11).
public protocol LockPreferencesProviding: AnyObject {
    var countdownSeconds: Int { get }
    var unlockMode: UnlockMode { get }
}

/// Cancelable timer handle.
public protocol LockTimerToken: AnyObject {
    func cancel()
}

/// Timer seam so all timing is injectable and TEST-U1 is deterministic. The app
/// uses a main-queue implementation; tests use a manual one. Actions run on the
/// main thread (the machine is `@MainActor`).
public protocol LockTimerScheduling {
    func scheduleOneShot(after seconds: TimeInterval, _ action: @escaping () -> Void) -> LockTimerToken
    func scheduleRepeating(every seconds: TimeInterval, _ action: @escaping () -> Void) -> LockTimerToken
}

// MARK: - Intents

/// External events fed to the machine (FSM-2). All timed transitions
/// (countdown finish, drain expiry, teardown completion, heartbeat) are driven
/// internally via the injected scheduler, not via intents.
public enum Intent: Equatable, Sendable {
    case permissionStatusChanged(PermissionStatus)
    case lockRequested                  // FR-1
    case cancelCountdown                // FR-2
    case unlockHoldBegan                // FR-7a mousedown
    case unlockHoldProgress(Double)     // FR-7a ring fill
    case unlockHoldCancelled            // FR-7a early release / cursor exit
    case unlockHoldCompleted            // FR-7a hold done (mouse path — no drain)
    case doubleClickUnlock              // FR-7b
    case unlockRequestedByHotkey        // FR-8 (REV-3 drain)
    case tapInterrupted                 // EC-3 / TAP-5
    case systemWillSleepOrLock          // EC-4 / EC-8
    case watchdogForcedUnlock           // FR-9c reconcile (EDGE-1)
}

// MARK: - State machine

/// Source of truth for *UI* state (ARCH-2). `@MainActor`; every mutation of
/// `state` happens on the main thread. Enforcement facts live separately in
/// `LockEnforcement`, which the watchdog touches off-main (REV-1).
@MainActor
public final class LockStateMachine: ObservableObject {
    @Published public private(set) var state: LockState

    /// Constants (FSM-1, REV-3).
    private let drainDuration: TimeInterval = 0.25
    private let teardownDuration: TimeInterval = 0.10
    private let heartbeatInterval: TimeInterval = 1.0

    private let tap: LockTapControlling
    private let power: PowerAsserting
    private let watchdog: LockWatchdogControlling
    private let preferences: LockPreferencesProviding
    private let enforcement: LockEnforcement
    private let scheduler: LockTimerScheduling

    private var countdownToken: LockTimerToken?
    private var drainToken: LockTimerToken?
    private var teardownToken: LockTimerToken?
    private var heartbeatToken: LockTimerToken?

    /// Last known unlocked-family status, so a teardown returns to the correct
    /// S0/S1 surface (and never restores a locked state — DATA-2).
    private var lastUnlockedStatus: PermissionStatus

    public init(
        tap: LockTapControlling,
        power: PowerAsserting,
        watchdog: LockWatchdogControlling,
        preferences: LockPreferencesProviding,
        enforcement: LockEnforcement,
        scheduler: LockTimerScheduling,
        initialPermission: PermissionStatus = .ready
    ) {
        self.tap = tap
        self.power = power
        self.watchdog = watchdog
        self.preferences = preferences
        self.enforcement = enforcement
        self.scheduler = scheduler
        self.lastUnlockedStatus = initialPermission
        self.state = initialPermission.canLock
            ? .unlockedReady
            : .unlockedNeedsPermission(initialPermission)

        // Tap callbacks are dispatched to main by the controller; bounce them
        // back in as intents.
        tap.onUnlockHotkey = { [weak self] in self?.handle(.unlockRequestedByHotkey) }
        tap.onTapInterrupted = { [weak self] in self?.handle(.tapInterrupted) }
    }

    /// Mirror used by the REV-9 binding-update guard.
    public var isUnlocked: Bool { state.isUnlocked }

    // MARK: - Intent handling (serialized via @MainActor)

    public func handle(_ intent: Intent) {
        switch intent {
        case let .permissionStatusChanged(status):
            lastUnlockedStatus = status
            if state.isUnlocked { state = currentUnlockedState() }

        case .lockRequested:
            // FR-4 / FSM-3: only from a ready state, never while needs-permission
            // or already in a lock sub-state.
            guard state == .unlockedReady else { return }
            beginLockSequence()

        case .cancelCountdown:
            guard case .countingDown = state else { return }
            countdownToken?.cancel(); countdownToken = nil
            state = .unlockedReady

        case .unlockHoldBegan:
            guard state == .locked else { return }
            state = .confirmingUnlock(progress: 0)

        case let .unlockHoldProgress(progress):
            guard case .confirmingUnlock = state else { return }
            state = .confirmingUnlock(progress: min(max(progress, 0), 1))

        case .unlockHoldCancelled:
            guard case .confirmingUnlock = state else { return }
            state = .locked

        case .unlockHoldCompleted:
            // Mouse path: no chord tail, so skip the drain (FSM-5).
            guard state == .locked || isConfirming else { return }
            beginTeardown()

        case .doubleClickUnlock:
            guard state == .locked || isConfirming else { return }
            beginTeardown()

        case .unlockRequestedByHotkey:
            // FSM-3: no-op during drain/teardown; the tap is already committed.
            guard state == .locked || isConfirming else { return }
            beginDrain()

        case .tapInterrupted, .systemWillSleepOrLock:
            guard state.isLockedFamily else { return }
            beginTeardown()

        case .watchdogForcedUnlock:
            guard state.isLockedFamily else { return }
            reconcileForcedUnlock()
        }
    }

    // MARK: - Lock sequence

    private func beginLockSequence() {
        let seconds = preferences.countdownSeconds
        if seconds <= 0 {
            enterLocked() // FSM-2 alt path: countdown Off
        } else {
            state = .countingDown(remaining: TimeInterval(seconds))
            countdownToken = scheduler.scheduleRepeating(every: 1.0) { [weak self] in
                self?.countdownTick()
            }
        }
    }

    private func countdownTick() {
        guard case let .countingDown(remaining) = state else { return }
        let next = remaining - 1
        if next <= 0 {
            countdownToken?.cancel(); countdownToken = nil
            enterLocked()
        } else {
            state = .countingDown(remaining: next)
        }
    }

    private func enterLocked() {
        // Never fake a lock (FR-18): if the tap won't install, fall back.
        guard tap.installTap() else {
            state = currentUnlockedState()
            return
        }
        enforcement.isLocked = true
        power.beginAssertion()
        watchdog.start()
        heartbeatToken = scheduler.scheduleRepeating(every: heartbeatInterval) { [weak self] in
            self?.watchdog.heartbeat()
        }
        state = .locked
    }

    // MARK: - Unlock paths

    private func beginDrain() {
        // Tap stays installed and dropping for the whole window (REV-3).
        state = .unlockingDrain
        drainToken = scheduler.scheduleOneShot(after: drainDuration) { [weak self] in
            self?.drainElapsed()
        }
    }

    private func drainElapsed() {
        drainToken?.cancel(); drainToken = nil
        beginTeardown()
    }

    private func beginTeardown() {
        drainToken?.cancel(); drainToken = nil
        state = .tearingDown
        runTeardownEffects()
        teardownToken = scheduler.scheduleOneShot(after: teardownDuration) { [weak self] in
            self?.finishTeardown()
        }
    }

    private func runTeardownEffects() {
        heartbeatToken?.cancel(); heartbeatToken = nil
        watchdog.stop()
        tap.removeTap()
        power.endAssertion()
        enforcement.isLocked = false
    }

    private func finishTeardown() {
        teardownToken?.cancel(); teardownToken = nil
        state = currentUnlockedState()
    }

    /// Watchdog starvation (EDGE-1): the watchdog already stopped the tap,
    /// released power, and cleared `LockEnforcement` off-main. We just drop our
    /// own timers/handles (idempotently) and snap straight to unlocked — no
    /// teardown delay, and never touching `@Published` from off-main (this runs
    /// on main, triggered by the `.kbStateForcedUnlocked` observer).
    private func reconcileForcedUnlock() {
        drainToken?.cancel(); drainToken = nil
        runTeardownEffects()
        state = currentUnlockedState()
    }

    // MARK: - Helpers

    private var isConfirming: Bool {
        if case .confirmingUnlock = state { return true }
        return false
    }

    private func currentUnlockedState() -> LockState {
        lastUnlockedStatus.canLock ? .unlockedReady : .unlockedNeedsPermission(lastUnlockedStatus)
    }
}
