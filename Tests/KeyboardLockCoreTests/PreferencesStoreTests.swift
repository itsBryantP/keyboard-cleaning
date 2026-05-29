import XCTest
import CoreGraphics
@testable import KeyboardLockCore

/// TEST-U3 — round-trip every DATA-1 key through an isolated in-memory
/// UserDefaults suite.
@MainActor
final class PreferencesStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    func testDefaultsWhenEmpty() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertEqual(store.countdownSeconds, 3)       // D-2
        XCTAssertEqual(store.unlockMode, .hold)
        XCTAssertEqual(store.unlockHotkey, .defaultUnlock) // D-4
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertTrue(store.showMenuBarItem)
    }

    func testRoundTripsAllKeys() {
        let defaults = makeDefaults()
        let custom = HotkeyBinding(keyCode: 1 /* S */, requiredFlags: [.maskCommand, .maskShift])

        let store = PreferencesStore(defaults: defaults)
        store.countdownSeconds = 5
        store.unlockMode = .doubleClick
        store.unlockHotkey = custom
        store.launchAtLogin = true
        store.showMenuBarItem = false

        // A fresh store over the same suite must observe the persisted values.
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.countdownSeconds, 5)
        XCTAssertEqual(reloaded.unlockMode, .doubleClick)
        XCTAssertEqual(reloaded.unlockHotkey, custom)
        XCTAssertTrue(reloaded.launchAtLogin)
        XCTAssertFalse(reloaded.showMenuBarItem)
    }

    func testInvalidCountdownFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set(4, forKey: "prefs.countdownSeconds") // not in {0,1,3,5}
        XCTAssertEqual(PreferencesStore(defaults: defaults).countdownSeconds, 3)
    }

    func testPersistedModifierlessHotkeyFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set(37, forKey: "prefs.unlockHotkey.keyCode")
        defaults.set(UInt64(0), forKey: "prefs.unlockHotkey.flags") // no modifiers (FR-8b)
        XCTAssertEqual(PreferencesStore(defaults: defaults).unlockHotkey, .defaultUnlock)
    }

    func testResetHotkeyToDefault() {
        let store = PreferencesStore(defaults: makeDefaults())
        store.unlockHotkey = HotkeyBinding(keyCode: 1, requiredFlags: [.maskCommand])
        store.resetHotkeyToDefault()
        XCTAssertEqual(store.unlockHotkey, .defaultUnlock)
    }
}
