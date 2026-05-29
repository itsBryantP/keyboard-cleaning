import XCTest
import CoreGraphics
@testable import KeyboardLockCore

/// TEST-U2 — exact match, modifier mismatch, and flag-mask edge cases
/// (numeric-keypad bit, caps-lock, fn) against the default ⌃⌥⌘L binding.
final class HotkeyMatcherTests: XCTestCase {
    private let binding = HotkeyBinding.defaultUnlock // ⌃⌥⌘L, keyCode 37
    private let chord: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    private func event(_ keyCode: CGKeyCode, _ flags: CGEventFlags) -> KeyEvent {
        KeyEvent(keyCode: keyCode, flags: flags)
    }

    func testExactMatch() {
        XCTAssertTrue(HotkeyMatcher.matches(event(37, chord), against: binding))
    }

    func testWrongKeyCodeDoesNotMatch() {
        XCTAssertFalse(HotkeyMatcher.matches(event(38, chord), against: binding))
    }

    func testMissingModifierDoesNotMatch() {
        XCTAssertFalse(
            HotkeyMatcher.matches(event(37, [.maskControl, .maskAlternate]), against: binding)
        )
    }

    func testExtraChordModifierDoesNotMatch() {
        // Holding shift in addition to the chord changes the chord bits → no match.
        XCTAssertFalse(
            HotkeyMatcher.matches(event(37, chord.union(.maskShift)), against: binding)
        )
    }

    func testFnHeldStillMatches() {
        // REV-12: a resting finger on the globe/fn key must not break unlock.
        XCTAssertTrue(
            HotkeyMatcher.matches(event(37, chord.union(.maskSecondaryFn)), against: binding)
        )
    }

    func testCapsLockLatchStillMatches() {
        XCTAssertTrue(
            HotkeyMatcher.matches(event(37, chord.union(.maskAlphaShift)), against: binding)
        )
    }

    func testNumericKeypadBitStillMatches() {
        XCTAssertTrue(
            HotkeyMatcher.matches(event(37, chord.union(.maskNumericPad)), against: binding)
        )
    }

    func testCombinedDeviceBitsStillMatch() {
        let noisy = chord.union([.maskSecondaryFn, .maskAlphaShift, .maskNumericPad, .maskNonCoalesced])
        XCTAssertTrue(HotkeyMatcher.matches(event(37, noisy), against: binding))
    }
}
