import Foundation

/// KeyboardLockCore — pure, UI-free logic for KeyboardLock.
///
/// Per SPEC ARCH-5, the testable core (state machine, hotkey matcher,
/// enforcement store, watchdog, preferences) lives here so it can be exercised
/// with `swift test` (SPEC §9.5 / TEST-C) against mocked collaborators. AppKit,
/// SwiftUI, IOKit, and CGEventTap-thread glue live in the `KeyboardLock.app`
/// target, which links this package.
public enum KeyboardLockCore {
    /// Marker so the module is non-empty and importable from the scaffold.
    public static let scaffoldVersion = "0.1.0"
}
