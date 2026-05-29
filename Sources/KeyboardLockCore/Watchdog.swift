import Foundation
import os

/// In-process watchdog (FR-9c, D-3, EDGE-1). A `DispatchSourceTimer` on a
/// dedicated serial queue checks that the main thread is still heartbeating; on
/// starvation it force-restores the keyboard **without ever touching
/// `@Published` / AppKit** (REV-1, REV-11).
///
/// On starvation the watchdog:
///  1. clears the enforcement facts in one locked step (`clearForForceStop`),
///     getting back the held IOPM assertion id;
///  2. invokes the injected, thread-safe `forceStop(assertionID:)` — wired in
///     the app to tear the tap down (`LockController.forceStopFromWatchdog`) and
///     release the power assertion off-main;
///  3. posts `.kbStateForcedUnlocked` so the main actor reconciles the UI later.
///
/// It depends only on `LockEnforcement`, an injected `MonotonicClock`, and the
/// two injected actions — no `@MainActor` coupling (ARCH-5). `forceStop` fires
/// at most once per lock session.
public final class Watchdog: LockWatchdogControlling, @unchecked Sendable {
    /// Thread-safe teardown action; receives the IOPM assertion id to release
    /// (0 if none). Must be safe to call off the main thread.
    public typealias ForceStop = @Sendable (_ assertionID: UInt32) -> Void

    private struct State {
        var lastHeartbeatAt: Double = 0
        var running: Bool = false
        var fired: Bool = false
    }

    private let enforcement: LockEnforcement
    private let clock: MonotonicClock
    private let starvationThreshold: Double
    private let checkInterval: Double
    private let forceStop: ForceStop
    private let notify: @Sendable () -> Void

    private let queue = DispatchQueue(label: "com.itsbryantp.keyboardlock.watchdog")
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var timer: DispatchSourceTimer?

    public init(
        enforcement: LockEnforcement,
        clock: MonotonicClock = SystemMonotonicClock(),
        starvationThreshold: Double = 5.0,
        checkInterval: Double = 0.5,
        forceStop: @escaping ForceStop,
        notify: @escaping @Sendable () -> Void = { NotificationCenter.default.post(name: .kbStateForcedUnlocked, object: nil) }
    ) {
        self.enforcement = enforcement
        self.clock = clock
        self.starvationThreshold = starvationThreshold
        self.checkInterval = checkInterval
        self.forceStop = forceStop
        self.notify = notify
    }

    // MARK: - LockWatchdogControlling

    /// Created on entry to `locked`. Records an initial heartbeat so a slow
    /// first beat doesn't trip the threshold.
    public func start() {
        state.withLock {
            $0.lastHeartbeatAt = clock.now()
            $0.running = true
            $0.fired = false
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + checkInterval, repeating: checkInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    /// Torn down on exit from `locked`.
    public func stop() {
        state.withLock { $0.running = false }
        timer?.cancel()
        timer = nil
    }

    /// Called once per second from the main thread (driven by the state
    /// machine's heartbeat timer). Updates the monotonic timestamp.
    public func heartbeat() {
        let t = clock.now()
        state.withLock { $0.lastHeartbeatAt = t }
    }

    // MARK: - Starvation check

    /// One watchdog evaluation. The production timer calls this every
    /// `checkInterval`; TEST-U5 calls it directly after advancing a fake clock.
    func tick() {
        let shouldFire: Bool = state.withLock { st in
            guard st.running, !st.fired else { return false }
            guard clock.now() - st.lastHeartbeatAt > starvationThreshold else { return false }
            // Latch so the teardown can never run twice, and stop checking.
            st.fired = true
            st.running = false
            return true
        }
        guard shouldFire else { return }

        // Keyboard restoration must not depend on the main thread (EDGE-1).
        let assertionID = enforcement.clearForForceStop()
        forceStop(assertionID)
        notify()
    }
}
