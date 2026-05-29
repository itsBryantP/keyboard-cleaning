import XCTest
import KeyboardLockCore
@testable import KeyboardLock

/// PowerManager round-trips a real IOPMAssertion (allowed for any process) and
/// records / clears the handle in LockEnforcement (EDGE-2), including the
/// idempotency the watchdog-forced reconcile relies on.
final class PowerManagerTests: XCTestCase {

    func testBeginStoresAssertionAndEndClearsIt() {
        let enforcement = LockEnforcement()
        let power = PowerManager(enforcement: enforcement)

        power.beginAssertion()
        XCTAssertNotEqual(enforcement.iopmAssertionID, 0, "an assertion id should be stored while locked")

        power.endAssertion()
        XCTAssertEqual(enforcement.iopmAssertionID, 0, "the id is cleared on release")
    }

    func testBeginIsIdempotent() {
        let enforcement = LockEnforcement()
        let power = PowerManager(enforcement: enforcement)

        power.beginAssertion()
        let first = enforcement.iopmAssertionID
        power.beginAssertion() // second begin must not replace / leak
        XCTAssertEqual(enforcement.iopmAssertionID, first)
        power.endAssertion()
    }

    func testEndWithoutBeginIsHarmless() {
        let enforcement = LockEnforcement()
        let power = PowerManager(enforcement: enforcement)
        power.endAssertion() // no-op, no crash
        XCTAssertEqual(enforcement.iopmAssertionID, 0)
    }
}
