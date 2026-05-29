import CoreGraphics
import ApplicationServices
import IOKit.hid

/// Real implementation of the silent permission checks and the REV-10
/// tap-creation probe, backed by the system frameworks. Kept in the core
/// package (it needs only CoreGraphics / ApplicationServices / IOKit, no
/// AppKit) so it can be the production collaborator behind `PermissionProbing`
/// while `PermissionEvaluator` stays trivially testable with a fake.
public struct SystemPermissionProbe: PermissionProbing, PermissionRequesting {
    public init() {}

    // MARK: - Silent checks (PERM-1)

    public func isAccessibilityGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public func isInputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    // MARK: - Tap-creation probe (REV-10)

    /// A silent `AXIsProcessTrusted == true` is necessary but not sufficient:
    /// after Accessibility is first granted, `CGEvent.tapCreate` at
    /// `.cghidEventTap` often fails until the app is relaunched. We confirm by
    /// installing a throwaway `.listenOnly` tap and tearing it straight back
    /// down. No run loop is started, so the no-op callback never actually runs.
    public func tapCreationProbeSucceeds() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // Non-capturing closure → usable as a C function pointer. listenOnly,
        // so it would just pass the event through if it ever fired.
        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            return false
        }

        // Tear the probe tap straight back down — it was only ever a feasibility
        // check (PERM-4 step 2).
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return true
    }

    // MARK: - Requests (PERM-4)

    /// Triggers the OS Accessibility prompt the first time per installation.
    public func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
