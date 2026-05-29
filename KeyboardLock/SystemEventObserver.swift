import AppKit

/// Observes the system events that must force-unlock the keyboard (EDGE-2,
/// EDGE-4, REV-19). Pure glue: it exposes two closures the app wires to the
/// state machine and a defensive wake backstop.
///
/// - `willSleep` / `screenIsLocked` → `onSleepOrScreenLock` (tear down before
///   sleep / at the login window, EC-4 / EC-8).
/// - `didWake` → `onWake`. Because `willSleepNotification` is only posted ~1 s
///   before sleep and macOS doesn't wait for observers (REV-19), the will-sleep
///   teardown is best-effort; the wake handler is the backstop that guarantees
///   "comes up Unlocked on wake" (EC-4).
final class SystemEventObserver {
    var onSleepOrScreenLock: (() -> Void)?
    var onWake: (() -> Void)?

    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.onSleepOrScreenLock?() }
        )
        workspaceTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.onWake?() }
        )

        // EDGE-4: lock screen / login window.
        let distributed = DistributedNotificationCenter.default()
        distributedTokens.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in self?.onSleepOrScreenLock?() }
        )
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { workspaceCenter.removeObserver($0) }
        let distributed = DistributedNotificationCenter.default()
        distributedTokens.forEach { distributed.removeObserver($0) }
        workspaceTokens.removeAll()
        distributedTokens.removeAll()
        started = false
    }

    deinit { stop() }
}
