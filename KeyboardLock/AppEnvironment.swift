import AppKit
import Combine
import KeyboardLockCore
import ServiceManagement

/// Assembles and wires the runtime object graph (ARCH-2/ARCH-5). App-lifetime
/// root, held as a `@StateObject`. Owns enforcement, controller, power,
/// watchdog, observers, permissions, preferences, the scheduler, and the state
/// machine, and connects the cross-thread signals back onto the main actor.
@MainActor
final class AppEnvironment: ObservableObject {
    let enforcement: LockEnforcement
    let preferences: PreferencesStore
    let permissions: PermissionsService
    let controller: LockController
    let power: PowerManager
    let watchdog: Watchdog
    let observer: SystemEventObserver
    let scheduler: MainQueueScheduler
    let stateMachine: LockStateMachine

    private let panelController: LockedPanelController
    private var menuBar: MenuBarController?
    private var cancellables: Set<AnyCancellable> = []
    private var forcedUnlockObserver: NSObjectProtocol?

    init() {
        let preferences = PreferencesStore()
        let enforcement = LockEnforcement(binding: preferences.unlockHotkey)
        let permissions = PermissionsService()
        let controller = LockController(enforcement: enforcement)
        let power = PowerManager(enforcement: enforcement)
        let scheduler = MainQueueScheduler()

        // Watchdog teardown runs off-main using only thread-safe calls (EDGE-1).
        let watchdog = Watchdog(enforcement: enforcement, forceStop: { assertionID in
            controller.forceStopFromWatchdog()
            PowerManager.releaseAssertion(id: assertionID)
        })

        let stateMachine = LockStateMachine(
            tap: controller,
            power: power,
            watchdog: watchdog,
            preferences: preferences,
            enforcement: enforcement,
            scheduler: scheduler,
            initialPermission: permissions.status
        )

        self.enforcement = enforcement
        self.preferences = preferences
        self.permissions = permissions
        self.controller = controller
        self.power = power
        self.watchdog = watchdog
        self.observer = SystemEventObserver()
        self.scheduler = scheduler
        self.stateMachine = stateMachine
        self.panelController = LockedPanelController(
            stateMachine: stateMachine,
            preferences: preferences,
            enforcement: enforcement
        )

        // REV-9: controller subscribes to unlock-hotkey changes.
        controller.bindUnlockHotkey(from: preferences)
        createMenuBar()
        wireUp()
    }

    private func createMenuBar() {
        menuBar = MenuBarController(
            enforcement: enforcement,
            stateMachine: stateMachine,
            onShowMainWindow: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            },
            onOpenPreferences: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            onUnlockViaPanel: { [panelController] in panelController.surfaceForUnlock() }
        )
        // install / remove is driven by the showMenuBarItem preference (REV-14).
    }

    private func wireUp() {
        // Permission status → state machine (drives S0 ↔ S1 while unlocked).
        permissions.$status
            .sink { [stateMachine] status in stateMachine.handle(.permissionStatusChanged(status)) }
            .store(in: &cancellables)

        // Sleep / screen-lock → force unlock (EC-4 / EC-8); wake → backstop.
        observer.onSleepOrScreenLock = { [stateMachine] in stateMachine.handle(.systemWillSleepOrLock) }
        observer.onWake = { [weak self] in self?.handleWake() }
        observer.start()

        // Watchdog forced-unlock reconcile (REV-11): the watchdog posts off its
        // queue; reconcile on the main actor.
        forcedUnlockObserver = NotificationCenter.default.addObserver(
            forName: .kbStateForcedUnlocked, object: nil, queue: .main
        ) { [stateMachine] _ in
            MainActor.assumeIsolated { stateMachine.handle(.watchdogForcedUnlock) }
        }

        // Show / hide the floating panel as we enter / leave the locked family
        // (UI-3). The published value is the upcoming state.
        stateMachine.$state
            .sink { [weak self] state in
                if state.isLockedFamily {
                    self?.panelController.show()
                } else {
                    self?.panelController.hide()
                }
                // Immediate icon refresh so there's no 250 ms lag (REV-11).
                self?.menuBar?.refresh()
            }
            .store(in: &cancellables)

        // REV-14: show / hide the menu bar item per preference.
        preferences.$showMenuBarItem
            .sink { [weak self] show in
                if show { self?.menuBar?.install() } else { self?.menuBar?.remove() }
            }
            .store(in: &cancellables)

        // Launch at login via SMAppService (PRD §5.7). Fires with the current
        // value on subscribe, so registration tracks the stored preference.
        preferences.$launchAtLogin
            .sink { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("KeyboardLock: launch-at-login update failed: \(error)")
                }
            }
            .store(in: &cancellables)

        permissions.startMonitoring()
    }

    /// REV-19 backstop: guarantee we come up unlocked on wake and that no tap
    /// somehow survived sleep.
    private func handleWake() {
        stateMachine.handle(.systemWillSleepOrLock) // tears down if still locked
        if enforcement.tapInstalled {
            controller.forceStopFromWatchdog()
            power.endAssertion()
        }
    }

    deinit {
        if let forcedUnlockObserver {
            NotificationCenter.default.removeObserver(forcedUnlockObserver)
        }
    }
}
