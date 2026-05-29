import CoreGraphics

/// Shared CGEventTap configuration (TAP-1, TAP-2).
public enum TapConfiguration {
    /// Events the locked tap is interested in. Mouse events are deliberately
    /// excluded so the mouse keeps working (FR-7). `systemDefined` is included
    /// only to catch and drop media / brightness keys; non-media systemDefined
    /// events are passed through by the callback (TAP-3 step 2).
    /// `NX_SYSDEFINED` — the system-defined event type (media / brightness
    /// keys). It is not a named `CGEventType` case, so we reference it by raw
    /// value both here and in the callback's type check.
    public static let systemDefinedEventTypeRawValue: UInt32 = 14

    public static let lockedEventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)
        | (UInt64(1) << UInt64(systemDefinedEventTypeRawValue))

    /// The HID-level tap point (lowest user-space level) and head insertion so
    /// we run before any other installed taps (TAP-1).
    public static let tapLocation: CGEventTapLocation = .cghidEventTap
    public static let tapPlacement: CGEventTapPlacement = .headInsertEventTap
}
