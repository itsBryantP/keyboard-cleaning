import XCTest
import KeyboardLockCore
@testable import KeyboardLock

/// AX-2 — the state→announcement mapping speaks the meaningful transitions and
/// stays quiet for transient / per-tick states so VoiceOver isn't spammed.
final class AccessibilityAnnouncerTests: XCTestCase {
    func testSpokenStates() {
        XCTAssertEqual(AccessibilityAnnouncer.message(for: .unlockedReady)?.key, "ready")
        XCTAssertEqual(AccessibilityAnnouncer.message(for: .locked)?.key, "locked")
        XCTAssertEqual(AccessibilityAnnouncer.message(for: .countingDown(remaining: 3))?.key, "countingDown")
        XCTAssertEqual(AccessibilityAnnouncer.message(for: .unlockingDrain)?.key, "unlocking")
        XCTAssertEqual(AccessibilityAnnouncer.message(for: .unlockedNeedsPermission(.needsRelaunch))?.key, "needsPermission")
    }

    func testSilentStates() {
        XCTAssertNil(AccessibilityAnnouncer.message(for: .confirmingUnlock(progress: 0.5)))
        XCTAssertNil(AccessibilityAnnouncer.message(for: .tearingDown))
    }

    func testCountdownKeyIsStableAcrossTicks() {
        // De-dup relies on the key being identical regardless of remaining time.
        XCTAssertEqual(
            AccessibilityAnnouncer.message(for: .countingDown(remaining: 3))?.key,
            AccessibilityAnnouncer.message(for: .countingDown(remaining: 1))?.key
        )
    }
}
