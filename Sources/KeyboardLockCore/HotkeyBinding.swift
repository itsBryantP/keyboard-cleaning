import CoreGraphics

/// The single keyboard chord allowed through the tap while locked (TAP-4).
///
/// `requiredFlags` is always normalized to `chordMask` — only ⇧⌃⌥⌘ are
/// significant. `fn` (`.maskSecondaryFn`), caps-lock, and numeric-keypad bits
/// are deliberately excluded (REV-12) so resting on the globe/fn key during
/// cleaning can never make a chord that *requires* `fn` and silently fail to
/// unlock. FR-8b ("at least one modifier") is checked against ⇧⌃⌥⌘ only.
public struct HotkeyBinding: Equatable, Sendable {
    public let keyCode: CGKeyCode
    public let requiredFlags: CGEventFlags

    /// The only flags that participate in matching. Everything else (fn,
    /// caps-lock latch, numeric-keypad, non-coalesced, device bits) is masked
    /// out of both the stored binding and the live comparison (TAP-4, REV-12).
    public static let chordMask: CGEventFlags =
        [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    /// Canonical initializer — normalizes the supplied flags to `chordMask`.
    public init(keyCode: CGKeyCode, requiredFlags: CGEventFlags) {
        self.keyCode = keyCode
        self.requiredFlags = requiredFlags.intersection(HotkeyBinding.chordMask)
    }

    /// Persistence codec helper (DATA-1): build from a stored `CGEventFlags`
    /// raw value. Normalizes like the canonical initializer.
    public init(keyCode: CGKeyCode, flagsRawValue: UInt64) {
        self.init(keyCode: keyCode, requiredFlags: CGEventFlags(rawValue: flagsRawValue))
    }

    /// Raw value of the normalized flags, for persistence (DATA-1).
    public var flagsRawValue: UInt64 { requiredFlags.rawValue }

    /// FR-8b: a binding is only valid if it carries at least one ⇧⌃⌥⌘ modifier.
    public var hasRequiredModifier: Bool { !requiredFlags.isEmpty }

    /// Validating factory used by the recorder (UI-8) and the persistence codec
    /// (TEST-U4): returns nil for a modifier-less chord (including an fn-only
    /// chord, since fn is stripped by normalization).
    public static func validated(keyCode: CGKeyCode, flags: CGEventFlags) -> HotkeyBinding? {
        let binding = HotkeyBinding(keyCode: keyCode, requiredFlags: flags)
        return binding.hasRequiredModifier ? binding : nil
    }

    /// Default unlock chord ⌃⌥⌘L (D-4): key code 37 = `kVK_ANSI_L`.
    public static let defaultUnlock = HotkeyBinding(
        keyCode: 37,
        requiredFlags: [.maskControl, .maskAlternate, .maskCommand]
    )
}
