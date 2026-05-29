import CoreGraphics

/// A lightweight, value-type view of a keyboard event, so the matcher (and its
/// tests, TEST-U2) need no real `CGEvent`. Built allocation-free by the tap
/// callback from `keyCode` + `flags` (TAP-3).
public struct KeyEvent: Equatable, Sendable {
    public let keyCode: CGKeyCode
    public let flags: CGEventFlags

    public init(keyCode: CGKeyCode, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

/// Pure decision: does a live key event match the configured unlock chord
/// (TAP-4)? Stateless and allocation-free so it stays well within the tap's
/// latency budget (TAP-5 / REV-6).
public enum HotkeyMatcher {
    /// Compares key code and the `chordMask`-normalized flags. Because both
    /// sides are intersected with `chordMask`, any fn / caps-lock / numeric-pad
    /// / device bits on the live event are ignored (REV-12) — the unlock fires
    /// whether or not those happen to be held.
    public static func matches(_ event: KeyEvent, against binding: HotkeyBinding) -> Bool {
        let flags = event.flags.intersection(HotkeyBinding.chordMask)
        return event.keyCode == binding.keyCode && flags == binding.requiredFlags
    }
}
