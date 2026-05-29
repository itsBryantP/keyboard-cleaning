import AppKit
import Combine
import KeyboardLockCore

/// Main-thread observable wrapper around the core permission checks (PERM-1,
/// PERM-4). Polls + requests Accessibility / Input Monitoring, runs the REV-10
/// tap-creation probe, opens System Settings deep links, and performs the
/// "restart to finish setup" relaunch. The pure evaluation and the real probe
/// live in `KeyboardLockCore`; this type owns the timing and AppKit side.
@MainActor
final class PermissionsService: ObservableObject {
    /// Current evaluated status. `.ready` ⇒ FSM S0; the others ⇒ the two S1
    /// variants (PERM-4).
    @Published private(set) var status: PermissionStatus

    private let probe: PermissionProbing & PermissionRequesting
    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    /// Poll cadence while the explainer is visible (PERM-4 step 5).
    private let pollInterval: TimeInterval = 2.0

    init(probe: (PermissionProbing & PermissionRequesting) = SystemPermissionProbe()) {
        self.probe = probe
        self.status = PermissionEvaluator.evaluate(using: probe)
    }

    deinit {
        pollTimer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - Evaluation

    /// Re-runs the silent check + probe and republishes `status`.
    func refresh() {
        let next = PermissionEvaluator.evaluate(using: probe)
        if next != status { status = next }
    }

    /// Begin polling + re-check on app activation. Called while the user is on
    /// the explainer so transitions feel instant after they return from System
    /// Settings (PERM-4 step 3 / step 5).
    func startMonitoring() {
        refresh()
        guard pollTimer == nil else { return }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Timer fires on the main runloop; hop onto the actor explicitly.
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    // MARK: - Requests & remediation (PERM-4)

    func requestAccessibility() {
        probe.promptForAccessibility()
        refresh()
    }

    func requestInputMonitoring() {
        probe.requestInputMonitoring()
        refresh()
    }

    func openAccessibilitySettings() { open(PermissionDeepLink.accessibility) }
    func openInputMonitoringSettings() { open(PermissionDeepLink.inputMonitoring) }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    /// PERM-4 step 2: launch a fresh instance and terminate this one so a
    /// just-granted Accessibility permission takes effect. The single-instance
    /// check (ARCH-1) hands off; the relaunch-handoff marker (REV-NEW-1) is
    /// wired in the single-instance phase. No launch agent is needed.
    func restartNow() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
