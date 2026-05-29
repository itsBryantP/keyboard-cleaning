import XCTest
import CoreGraphics
@testable import KeyboardLockCore

/// TEST-U4 — binding validation + persistence codec: reject modifier-less
/// chords, accept 1+ modifier chords, strip fn (REV-12), and round-trip the
/// flags raw value (DATA-1).
final class HotkeyBindingTests: XCTestCase {

    func testRejectsModifierlessBinding() {
        XCTAssertNil(HotkeyBinding.validated(keyCode: 37, flags: []))
    }

    func testRejectsFnOnlyBinding() {
        // fn is stripped by normalization, leaving no chord modifier → invalid.
        XCTAssertNil(HotkeyBinding.validated(keyCode: 37, flags: [.maskSecondaryFn]))
    }

    func testAcceptsSingleModifierBinding() {
        let binding = HotkeyBinding.validated(keyCode: 37, flags: [.maskCommand])
        XCTAssertEqual(binding?.requiredFlags, [.maskCommand])
        XCTAssertTrue(binding?.hasRequiredModifier ?? false)
    }

    func testNormalizationStripsFnAndDeviceBits() {
        let binding = HotkeyBinding(
            keyCode: 37,
            requiredFlags: [.maskCommand, .maskSecondaryFn, .maskAlphaShift, .maskNumericPad]
        )
        XCTAssertEqual(binding.requiredFlags, [.maskCommand])
    }

    func testFlagsRawValueRoundTrips() {
        let original = HotkeyBinding.defaultUnlock
        let restored = HotkeyBinding(keyCode: original.keyCode, flagsRawValue: original.flagsRawValue)
        XCTAssertEqual(original, restored)
    }

    func testDefaultUnlockIsControlOptionCommandL() {
        let d = HotkeyBinding.defaultUnlock
        XCTAssertEqual(d.keyCode, 37)
        XCTAssertEqual(d.requiredFlags, [.maskControl, .maskAlternate, .maskCommand])
        XCTAssertTrue(d.hasRequiredModifier)
    }
}
