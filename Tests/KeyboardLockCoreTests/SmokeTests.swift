import XCTest
@testable import KeyboardLockCore

/// Smoke test proving the package builds and is importable. Real coverage
/// (TEST-U1…U5) lands in later phases.
final class SmokeTests: XCTestCase {
    func testScaffoldVersion() {
        XCTAssertEqual(KeyboardLockCore.scaffoldVersion, "0.1.0")
    }
}
