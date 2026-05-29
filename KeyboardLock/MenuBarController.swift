import AppKit
import KeyboardLockCore

/// Owns the `NSStatusItem` (M1 / UI-5). The icon + pulse are driven by a
/// lightweight main-thread timer that reads `LockEnforcement.isLocked` (REV-11),
/// so a watchdog-forced unlock (which flips the flag off-main) restores the
/// "unlocked" icon as soon as main runs — without the watchdog touching AppKit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let enforcement: LockEnforcement
    private let stateMachine: LockStateMachine
    private let onShowMainWindow: () -> Void
    private let onOpenPreferences: () -> Void
    private let onUnlockViaPanel: () -> Void

    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var lastLocked: Bool?
    private var lockStartedAt: Date?

    init(
        enforcement: LockEnforcement,
        stateMachine: LockStateMachine,
        onShowMainWindow: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onUnlockViaPanel: @escaping () -> Void
    ) {
        self.enforcement = enforcement
        self.stateMachine = stateMachine
        self.onShowMainWindow = onShowMainWindow
        self.onOpenPreferences = onOpenPreferences
        self.onUnlockViaPanel = onUnlockViaPanel
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.wantsLayer = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refresh()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func remove() {
        pollTimer?.invalidate(); pollTimer = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    /// Reconcile icon + pulse from the enforcement flag (REV-11). Called by the
    /// 250 ms timer and immediately by the state machine on change (no lag).
    func refresh() {
        let locked = enforcement.isLocked
        guard let button = statusItem?.button else { return }

        if lastLocked != locked {
            button.image = MenuBarIcon.image(locked: locked)
            updatePulse(locked: locked, button: button)
            if locked, lockStartedAt == nil { lockStartedAt = Date() }
            if !locked { lockStartedAt = nil }
            lastLocked = locked
        }
    }

    private func updatePulse(locked: Bool, button: NSStatusBarButton) {
        button.layer?.removeAnimation(forKey: "pulse")
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard locked, !reduceMotion else { // AX-5: no pulse under Reduce Motion
            button.alphaValue = 1
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.6
        pulse.duration = 0.25 // 2 Hz round trip with autoreverse
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        button.layer?.add(pulse, forKey: "pulse")
    }

    // MARK: - NSMenuDelegate (rebuild per open so it reflects current state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let locked = enforcement.isLocked

        let header = NSMenuItem(title: headerTitle(locked: locked), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if locked {
            // REV-2: routes to the panel's HoldButton — never a direct unlock.
            menu.addItem(makeItem("Unlock Keyboard", #selector(unlockViaPanel)))
        } else {
            let lockItem = makeItem("Lock Keyboard", #selector(lockKeyboard))
            // FR-4 / FR-18: can't lock without permissions.
            lockItem.isEnabled = (stateMachine.state == .unlockedReady)
            menu.addItem(lockItem)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Show Main Window", #selector(showMainWindow)))
        menu.addItem(makeItem("Preferences…", #selector(openPreferences)))
        menu.addItem(makeItem("About KeyboardLock", #selector(showAbout)))
        menu.addItem(makeItem("Check for Updates…", #selector(checkForUpdates)))

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(makeItem("Stall main thread (6 s)", #selector(stallMainThread)))
        #endif

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit KeyboardLock", #selector(quit)))
    }

    private func headerTitle(locked: Bool) -> String {
        guard locked else { return "Keyboard: Active" }
        let elapsed = Int(Date().timeIntervalSince(lockStartedAt ?? Date()))
        return String(format: "Keyboard: Locked (%d:%02d)", elapsed / 60, elapsed % 60)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func lockKeyboard() { stateMachine.handle(.lockRequested) }
    @objc private func unlockViaPanel() { onUnlockViaPanel() }
    @objc private func showMainWindow() { onShowMainWindow() }
    @objc private func openPreferences() { onOpenPreferences() }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    @objc private func checkForUpdates() { UpdateChecker.openReleasesPage() }
    @objc private func quit() { NSApp.terminate(nil) }

    #if DEBUG
    @objc private func stallMainThread() { MainThreadStaller.stall(seconds: 6) }
    #endif
}
