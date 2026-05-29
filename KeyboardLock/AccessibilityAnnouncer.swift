import AppKit
import KeyboardLockCore

/// Posts high-priority VoiceOver announcements on lock-state transitions (AX-2).
enum AccessibilityAnnouncer {
    static func announce(_ message: String) {
        guard !message.isEmpty else { return }
        let element: Any = NSApp.keyWindow ?? NSApp as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    /// Coarse, de-duplicated message for a state. Returns nil for states that
    /// shouldn't interrupt (transient teardown, per-tick confirm progress).
    static func message(for state: LockState) -> (key: String, text: String)? {
        switch state {
        case .unlockedReady:
            return ("ready", "Keyboard is active.")
        case .unlockedNeedsPermission:
            return ("needsPermission", "Permissions needed to lock the keyboard.")
        case .countingDown:
            return ("countingDown", "Locking the keyboard.")
        case .locked:
            return ("locked", "Keyboard locked. Safe to clean.")
        case .unlockingDrain:
            return ("unlocking", "Unlocking.")
        case .confirmingUnlock, .tearingDown:
            return nil
        }
    }
}
