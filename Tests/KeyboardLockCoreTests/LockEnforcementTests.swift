import XCTest
@testable import KeyboardLockCore

/// Sanity coverage for the any-thread enforcement store (REV-1). Concurrency
/// correctness is exercised indirectly by the watchdog tests (TEST-U5) and the
/// integration tests; here we confirm the accessors and the force-stop snapshot
/// behave, including under concurrent access.
final class LockEnforcementTests: XCTestCase {

    func testDefaultsAndBindingRoundTrip() {
        let enforcement = LockEnforcement()
        XCTAssertEqual(enforcement.binding, .defaultUnlock)
        XCTAssertFalse(enforcement.isLocked)
        XCTAssertFalse(enforcement.tapInstalled)
        XCTAssertEqual(enforcement.iopmAssertionID, 0)

        let custom = HotkeyBinding(keyCode: 1, requiredFlags: [.maskCommand, .maskShift])
        enforcement.binding = custom
        XCTAssertEqual(enforcement.binding, custom)
    }

    func testClearForForceStopReturnsAssertionAndResetsFlags() {
        let enforcement = LockEnforcement()
        enforcement.isLocked = true
        enforcement.tapInstalled = true
        enforcement.rearming = true
        enforcement.iopmAssertionID = 4242

        let released = enforcement.clearForForceStop()

        XCTAssertEqual(released, 4242)
        XCTAssertFalse(enforcement.isLocked)
        XCTAssertFalse(enforcement.tapInstalled)
        XCTAssertFalse(enforcement.rearming)
        XCTAssertEqual(enforcement.iopmAssertionID, 0)
    }

    func testTapTimeoutCounter() {
        let enforcement = LockEnforcement()
        XCTAssertEqual(enforcement.recordTapTimeout(), 1)
        XCTAssertEqual(enforcement.recordTapTimeout(), 2)
        XCTAssertEqual(enforcement.consecutiveTapTimeouts, 2)
        enforcement.resetTapTimeouts()
        XCTAssertEqual(enforcement.consecutiveTapTimeouts, 0)
    }

    func testConcurrentReadsAndWritesDoNotCrash() {
        let enforcement = LockEnforcement()
        let iterations = 10_000
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                enforcement.isLocked = (i % 4 == 0)
                _ = enforcement.binding
            } else {
                _ = enforcement.isLocked
                enforcement.binding = HotkeyBinding(keyCode: CGKeyCode(i % 128), requiredFlags: [.maskCommand])
            }
        }
        // Reaching here without a data-race crash is the assertion.
        XCTAssertEqual(enforcement.binding.requiredFlags, [.maskCommand])
    }
}
