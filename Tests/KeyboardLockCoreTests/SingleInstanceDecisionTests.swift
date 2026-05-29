import XCTest
@testable import KeyboardLockCore

/// Coverage for the single-instance / relaunch-handoff decision (REV-18,
/// REV-NEW-1).
final class SingleInstanceDecisionTests: XCTestCase {
    func testSoleInstanceProceeds() {
        XCTAssertEqual(.proceed, SingleInstanceDecision.decide(hasLiveSibling: false, handoffValid: false))
        // A stale marker with no sibling is irrelevant.
        XCTAssertEqual(.proceed, SingleInstanceDecision.decide(hasLiveSibling: false, handoffValid: true))
    }

    func testDoubleLaunchTerminatesSelf() {
        XCTAssertEqual(.terminateSelf, SingleInstanceDecision.decide(hasLiveSibling: true, handoffValid: false))
    }

    func testRelaunchHandoffSurvives() {
        XCTAssertEqual(.surviveAndClearMarker, SingleInstanceDecision.decide(hasLiveSibling: true, handoffValid: true))
    }
}
