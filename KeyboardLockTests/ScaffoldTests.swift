import XCTest
@testable import KeyboardLock

/// Host-target smoke test. The unit-logic suites (TEST-U1…U5) live in the
/// `KeyboardLockCore` Swift package and run via `swift test`; this Xcode test
/// target hosts the app and is the home for snapshot / accessibility tests in
/// later phases (TEST-S).
final class ScaffoldTests: XCTestCase {
    func testHostAppLinks() {
        XCTAssertTrue(true)
    }
}
