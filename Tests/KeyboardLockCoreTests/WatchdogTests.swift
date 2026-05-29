import XCTest
@testable import KeyboardLockCore

/// TEST-U5 — inject a fake clock + synthetic heartbeat gap and assert the
/// starvation teardown fires exactly once and touches only `LockEnforcement`
/// (no `@Published` / AppKit — guaranteed by construction; verified here via a
/// spy `forceStop`/`notify` and the cleared enforcement state). FR-9c, EC-2,
/// REV-1, REV-5.
final class WatchdogTests: XCTestCase {

    private final class FakeClock: MonotonicClock {
        private let lock = NSLock()
        private var value: Double = 0
        func set(_ v: Double) { lock.lock(); value = v; lock.unlock() }
        func now() -> Double { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Build a watchdog whose real timer is effectively dormant (huge interval)
    /// so the test drives `tick()` deterministically.
    private func makeWatchdog(
        clock: FakeClock,
        enforcement: LockEnforcement
    ) -> (Watchdog, () -> Int, () -> [UInt32], () -> Int) {
        let forceStopCount = OSCounter()
        let assertionIDs = OSBox<[UInt32]>([])
        let notifyCount = OSCounter()

        let watchdog = Watchdog(
            enforcement: enforcement,
            clock: clock,
            starvationThreshold: 5.0,
            checkInterval: 3600, // dormant real timer; we call tick() manually
            forceStop: { id in
                forceStopCount.increment()
                assertionIDs.mutate { $0.append(id) }
            },
            notify: { notifyCount.increment() }
        )
        return (watchdog, { forceStopCount.value }, { assertionIDs.value }, { notifyCount.value })
    }

    func testStarvationFiresForceStopExactlyOnce() {
        let clock = FakeClock()
        let enforcement = LockEnforcement()
        enforcement.isLocked = true
        enforcement.tapInstalled = true
        enforcement.iopmAssertionID = 4242

        let (watchdog, forceStops, ids, notifies) = makeWatchdog(clock: clock, enforcement: enforcement)
        watchdog.start()      // lastHeartbeatAt = 0
        watchdog.heartbeat()  // lastHeartbeatAt = 0

        clock.set(6.0)        // 6 s with no heartbeat > 5 s threshold
        watchdog.tick()
        watchdog.tick()       // subsequent checks must not re-fire
        watchdog.tick()

        XCTAssertEqual(forceStops(), 1, "forceStop must fire exactly once")
        XCTAssertEqual(notifies(), 1)
        XCTAssertEqual(ids(), [4242], "the held IOPM assertion id is handed to the teardown")
        // Enforcement was cleared off-main — keyboard restored regardless of main.
        XCTAssertFalse(enforcement.isLocked)
        XCTAssertFalse(enforcement.tapInstalled)
        XCTAssertEqual(enforcement.iopmAssertionID, 0)
        watchdog.stop()
    }

    func testNoStarvationWhenHeartbeatsKeepUp() {
        let clock = FakeClock()
        let enforcement = LockEnforcement()
        enforcement.isLocked = true

        let (watchdog, forceStops, _, notifies) = makeWatchdog(clock: clock, enforcement: enforcement)
        watchdog.start()

        clock.set(3.0); watchdog.heartbeat() // beat at t=3
        clock.set(7.0)                        // gap since last beat = 4 < 5
        watchdog.tick()

        XCTAssertEqual(forceStops(), 0)
        XCTAssertEqual(notifies(), 0)
        XCTAssertTrue(enforcement.isLocked)
        watchdog.stop()
    }

    func testStopPreventsFiring() {
        let clock = FakeClock()
        let enforcement = LockEnforcement()
        let (watchdog, forceStops, _, _) = makeWatchdog(clock: clock, enforcement: enforcement)
        watchdog.start()
        watchdog.heartbeat()
        watchdog.stop()

        clock.set(10.0)
        watchdog.tick()
        XCTAssertEqual(forceStops(), 0, "a stopped watchdog never fires")
    }

    func testRealTimerFiresOnRealStall() {
        // Uses the real SystemMonotonicClock and a short threshold to prove the
        // DispatchSourceTimer path actually fires without any manual tick().
        let enforcement = LockEnforcement()
        enforcement.isLocked = true
        let fired = expectation(description: "watchdog fired via its own timer")

        let watchdog = Watchdog(
            enforcement: enforcement,
            clock: SystemMonotonicClock(),
            starvationThreshold: 0.3,
            checkInterval: 0.1,
            forceStop: { _ in },
            notify: { fired.fulfill() }
        )
        watchdog.start()
        // Deliberately never heartbeat → starvation after ~0.3 s.
        wait(for: [fired], timeout: 3.0)
        watchdog.stop()
        XCTAssertFalse(enforcement.isLocked)
    }
}

// MARK: - Tiny thread-safe spies

private final class OSCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class OSBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ initial: T) { stored = initial }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&stored); lock.unlock() }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
}
