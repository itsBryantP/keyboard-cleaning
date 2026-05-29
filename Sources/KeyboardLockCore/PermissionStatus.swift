import Foundation

/// Result of evaluating the app's ability to install the keyboard tap.
///
/// Maps to FSM-1: `.ready` is state S0 (`unlockedReady`); the two non-ready
/// cases are the two S1 (`unlockedNeedsPermission`) variants called out in
/// PERM-4 / REV-10 — a genuinely missing permission vs. "granted but the tap
/// probe failed, so macOS needs a relaunch before locking can work."
public enum PermissionStatus: Equatable, Sendable {
    /// Accessibility + Input Monitoring granted AND the tap-creation probe
    /// passed (REV-10). The keyboard can actually be locked.
    case ready

    /// At least one permission is missing outright. Associated booleans report
    /// whether each is currently granted, so the explainer can show per-row
    /// check / cross status (PERM-4 step 3).
    case missingPermissions(accessibility: Bool, inputMonitoring: Bool)

    /// Both permissions report granted, but `CGEvent.tapCreate` still fails —
    /// macOS commonly requires a relaunch after Accessibility is first granted
    /// before tap creation actually succeeds (REV-10). Distinct remediation:
    /// "Restart to finish setup," not "grant a permission."
    case needsRelaunch

    /// True only in S0. Never show a "locked" UI unless this is true (FR-18).
    public var canLock: Bool { self == .ready }
}

/// System Settings deep links for the two privacy panes (PERM-1). Opened with
/// `NSWorkspace.shared.open` from the app target.
public enum PermissionDeepLink {
    public static let accessibility =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    public static let inputMonitoring =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
}

/// Silent, non-prompting permission queries plus the tap-creation probe. Kept
/// as a protocol so `PermissionEvaluator` can be unit-tested with a fake
/// (TEST-C) — the real system calls live in `SystemPermissionProbe`.
public protocol PermissionProbing {
    /// `AXIsProcessTrustedWithOptions(prompt: false)`.
    func isAccessibilityGranted() -> Bool
    /// `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == granted`.
    func isInputMonitoringGranted() -> Bool
    /// REV-10 probe: create a throwaway `.listenOnly` tap at `.cghidEventTap`
    /// and tear it straight back down; returns whether creation succeeded.
    func tapCreationProbeSucceeds() -> Bool
}

/// Prompting / request side, separated from the silent checks because it has
/// side effects (shows the OS prompt the first time) and is irrelevant to the
/// pure evaluator.
public protocol PermissionRequesting {
    func promptForAccessibility()
    func requestInputMonitoring()
}

/// Pure combiner from raw probe readings to a `PermissionStatus`.
///
/// The tap-creation probe (REV-10) is only consulted once both permissions
/// report granted — a missing permission short-circuits before the (more
/// expensive, and meaningless-when-ungranted) probe runs. TEST-C asserts both
/// the resulting status and that short-circuit.
public enum PermissionEvaluator {
    public static func evaluate(using probe: PermissionProbing) -> PermissionStatus {
        let accessibility = probe.isAccessibilityGranted()
        let inputMonitoring = probe.isInputMonitoringGranted()
        guard accessibility && inputMonitoring else {
            return .missingPermissions(
                accessibility: accessibility,
                inputMonitoring: inputMonitoring
            )
        }
        return probe.tapCreationProbeSucceeds() ? .ready : .needsRelaunch
    }
}
