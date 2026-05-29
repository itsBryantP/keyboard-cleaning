import XCTest
@testable import KeyboardLockCore

/// Unit coverage for the pure tap-timeout policy (TAP-5 / REV-6). The
/// CGEvent.tapEnable side of the contract is exercised by TEST-I3 (integration).
final class TapPolicyTests: XCTestCase {

    func testFirstTimeoutReEnablesWhenSuccessful() {
        XCTAssertEqual(
            TapPolicy.decideTapDisabledByTimeout(newConsecutiveCount: 1, reEnableSucceeded: true),
            .reEnableAfterTimeout
        )
    }

    func testFailedReEnableInterruptsImmediately() {
        XCTAssertEqual(
            TapPolicy.decideTapDisabledByTimeout(newConsecutiveCount: 1, reEnableSucceeded: false),
            .interrupt
        )
    }

    func testTrippingTheCapInterrupts() {
        XCTAssertEqual(
            TapPolicy.decideTapDisabledByTimeout(newConsecutiveCount: 3, reEnableSucceeded: true),
            .interrupt
        )
    }

    func testUnderCapKeepsReArming() {
        for count in 1..<TapPolicy.consecutiveTimeoutCap {
            XCTAssertEqual(
                TapPolicy.decideTapDisabledByTimeout(newConsecutiveCount: count, reEnableSucceeded: true),
                .reEnableAfterTimeout
            )
        }
    }
}
