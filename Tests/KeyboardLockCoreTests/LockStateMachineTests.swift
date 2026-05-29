import XCTest
@testable import KeyboardLockCore

/// TEST-U1 — every transition in SPEC §3.2 driven by synthetic intents + a
/// manual scheduler, with spy collaborators.
@MainActor
final class LockStateMachineTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeTap: LockTapControlling {
        var onUnlockHotkey: (() -> Void)?
        var onTapInterrupted: (() -> Void)?
        var installResult = true
        private(set) var installCount = 0
        private(set) var removeCount = 0
        func installTap() -> Bool { installCount += 1; return installResult }
        func removeTap() { removeCount += 1 }
    }

    private final class FakePower: PowerAsserting {
        private(set) var begun = 0
        private(set) var ended = 0
        func beginAssertion() { begun += 1 }
        func endAssertion() { ended += 1 }
    }

    private final class FakeWatchdog: LockWatchdogControlling {
        private(set) var started = 0
        private(set) var stopped = 0
        private(set) var heartbeats = 0
        func start() { started += 1 }
        func stop() { stopped += 1 }
        func heartbeat() { heartbeats += 1 }
    }

    private final class FakePrefs: LockPreferencesProviding {
        var countdownSeconds: Int
        var unlockMode: UnlockMode
        init(countdownSeconds: Int = 3, unlockMode: UnlockMode = .hold) {
            self.countdownSeconds = countdownSeconds
            self.unlockMode = unlockMode
        }
    }

    private final class ManualScheduler: LockTimerScheduling {
        final class Token: LockTimerToken {
            var cancelled = false
            func cancel() { cancelled = true }
        }
        private struct Entry { let token: Token; let repeating: Bool; let action: () -> Void }
        private var entries: [Entry] = []

        func scheduleOneShot(after seconds: TimeInterval, _ action: @escaping () -> Void) -> LockTimerToken {
            let token = Token(); entries.append(Entry(token: token, repeating: false, action: action)); return token
        }
        func scheduleRepeating(every seconds: TimeInterval, _ action: @escaping () -> Void) -> LockTimerToken {
            let token = Token(); entries.append(Entry(token: token, repeating: true, action: action)); return token
        }
        /// Fire (once) every pending one-shot.
        func fireOneShots() {
            let pending = entries.filter { !$0.token.cancelled && !$0.repeating }
            pending.forEach { $0.token.cancelled = true }
            pending.forEach { $0.action() }
            cleanup()
        }
        /// Simulate one period elapsing for every active repeating timer.
        func tickRepeating() {
            entries.filter { !$0.token.cancelled && $0.repeating }.forEach { $0.action() }
            cleanup()
        }
        private func cleanup() { entries.removeAll { $0.token.cancelled } }
    }

    // MARK: - Harness

    private func makeMachine(
        countdownSeconds: Int = 3,
        unlockMode: UnlockMode = .hold,
        permission: PermissionStatus = .ready
    ) -> (LockStateMachine, FakeTap, FakePower, FakeWatchdog, ManualScheduler, LockEnforcement) {
        let tap = FakeTap()
        let power = FakePower()
        let watchdog = FakeWatchdog()
        let prefs = FakePrefs(countdownSeconds: countdownSeconds, unlockMode: unlockMode)
        let scheduler = ManualScheduler()
        let enforcement = LockEnforcement()
        let machine = LockStateMachine(
            tap: tap, power: power, watchdog: watchdog, preferences: prefs,
            enforcement: enforcement, scheduler: scheduler, initialPermission: permission
        )
        return (machine, tap, power, watchdog, scheduler, enforcement)
    }

    /// Drive `machine` from ready into the fully locked state.
    private func lock(_ machine: LockStateMachine, _ scheduler: ManualScheduler, countdown: Int) {
        machine.handle(.lockRequested)
        for _ in 0..<countdown { scheduler.tickRepeating() }
    }

    // MARK: - Launch (FSM-2 entry)

    func testLaunchWithoutPermissionsStartsNeedsPermission() {
        let (machine, _, _, _, _, _) = makeMachine(
            permission: .missingPermissions(accessibility: false, inputMonitoring: false)
        )
        XCTAssertEqual(machine.state, .unlockedNeedsPermission(.missingPermissions(accessibility: false, inputMonitoring: false)))
    }

    func testLaunchWithPermissionsStartsReady() {
        let (machine, _, _, _, _, _) = makeMachine()
        XCTAssertEqual(machine.state, .unlockedReady)
    }

    // MARK: - Permission transitions (EC-3)

    func testNeedsPermissionToReadyOnGrant() {
        let (machine, _, _, _, _, _) = makeMachine(permission: .needsRelaunch)
        machine.handle(.permissionStatusChanged(.ready))
        XCTAssertEqual(machine.state, .unlockedReady)
    }

    func testReadyToNeedsPermissionOnRevoke() {
        let (machine, _, _, _, _, _) = makeMachine()
        machine.handle(.permissionStatusChanged(.missingPermissions(accessibility: false, inputMonitoring: true)))
        XCTAssertEqual(machine.state, .unlockedNeedsPermission(.missingPermissions(accessibility: false, inputMonitoring: true)))
    }

    // MARK: - Lock / countdown (FR-1, FR-2, FR-3)

    func testLockRequestEntersCountdownWithoutInstallingTap() {
        let (machine, tap, _, _, _, _) = makeMachine(countdownSeconds: 3)
        machine.handle(.lockRequested)
        XCTAssertEqual(machine.state, .countingDown(remaining: 3))
        XCTAssertEqual(tap.installCount, 0)
    }

    func testCancelDuringCountdownReturnsToReady() {
        let (machine, tap, power, _, scheduler, _) = makeMachine(countdownSeconds: 3)
        machine.handle(.lockRequested)
        scheduler.tickRepeating() // 3 -> 2
        machine.handle(.cancelCountdown)
        XCTAssertEqual(machine.state, .unlockedReady)
        XCTAssertEqual(tap.installCount, 0)
        XCTAssertEqual(power.begun, 0)
    }

    func testCountdownReachingZeroLocks() {
        let (machine, tap, power, watchdog, scheduler, enforcement) = makeMachine(countdownSeconds: 3)
        machine.handle(.lockRequested)
        scheduler.tickRepeating() // 3 -> 2
        XCTAssertEqual(machine.state, .countingDown(remaining: 2))
        scheduler.tickRepeating() // 2 -> 1
        scheduler.tickRepeating() // 1 -> 0 -> locked
        XCTAssertEqual(machine.state, .locked)
        XCTAssertEqual(tap.installCount, 1)
        XCTAssertEqual(power.begun, 1)
        XCTAssertEqual(watchdog.started, 1)
        XCTAssertTrue(enforcement.isLocked)
    }

    func testCountdownOffLocksImmediately() {
        let (machine, tap, _, _, _, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        XCTAssertEqual(machine.state, .locked)
        XCTAssertEqual(tap.installCount, 1)
    }

    func testHeartbeatFiresWhileLocked() {
        let (machine, _, _, watchdog, scheduler, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        scheduler.tickRepeating() // heartbeat timer is the only repeating timer now
        XCTAssertGreaterThanOrEqual(watchdog.heartbeats, 1)
    }

    func testInstallFailureDoesNotFakeLock() {
        let (machine, tap, power, watchdog, _, enforcement) = makeMachine(countdownSeconds: 0)
        tap.installResult = false
        machine.handle(.lockRequested)
        XCTAssertEqual(machine.state, .unlockedReady) // FR-18: never a fake lock
        XCTAssertEqual(power.begun, 0)
        XCTAssertEqual(watchdog.started, 0)
        XCTAssertFalse(enforcement.isLocked)
    }

    // MARK: - Mouse-hold unlock (FR-7a, FSM-5)

    func testHoldBeginProgressCancel() {
        let (machine, _, _, _, _, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        machine.handle(.unlockHoldBegan)
        XCTAssertEqual(machine.state, .confirmingUnlock(progress: 0))
        machine.handle(.unlockHoldProgress(0.5))
        XCTAssertEqual(machine.state, .confirmingUnlock(progress: 0.5))
        machine.handle(.unlockHoldCancelled)
        XCTAssertEqual(machine.state, .locked)
    }

    func testHoldCompleteSkipsDrainAndTearsDown() {
        let (machine, tap, power, _, scheduler, enforcement) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        machine.handle(.unlockHoldBegan)
        machine.handle(.unlockHoldCompleted)
        XCTAssertEqual(machine.state, .tearingDown) // no drain on the mouse path
        XCTAssertEqual(tap.removeCount, 1)
        XCTAssertEqual(power.ended, 1)
        XCTAssertFalse(enforcement.isLocked)
        scheduler.fireOneShots() // teardown completes
        XCTAssertEqual(machine.state, .unlockedReady)
    }

    // MARK: - Hotkey unlock drain (FR-8, REV-3)

    func testHotkeyUnlockKeepsTapInstalledThroughDrain() {
        let (machine, tap, _, _, scheduler, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        machine.handle(.unlockRequestedByHotkey)
        XCTAssertEqual(machine.state, .unlockingDrain)
        XCTAssertEqual(tap.removeCount, 0, "Tap must stay installed during the drain (REV-3)")

        scheduler.fireOneShots() // drain elapses -> tearingDown
        XCTAssertEqual(machine.state, .tearingDown)
        XCTAssertEqual(tap.removeCount, 1, "Tap removed only after the drain")

        scheduler.fireOneShots() // teardown completes
        XCTAssertEqual(machine.state, .unlockedReady)
    }

    func testHotkeyCallbackFromControllerDrivesDrain() {
        let (machine, tap, _, _, _, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        tap.onUnlockHotkey?() // simulate the controller's main-dispatched signal
        XCTAssertEqual(machine.state, .unlockingDrain)
    }

    // MARK: - Double-click unlock (FR-7b)

    func testDoubleClickUnlockTearsDown() {
        let (machine, tap, _, _, scheduler, _) = makeMachine(countdownSeconds: 0, unlockMode: .doubleClick)
        machine.handle(.lockRequested)
        machine.handle(.doubleClickUnlock)
        XCTAssertEqual(machine.state, .tearingDown)
        scheduler.fireOneShots()
        XCTAssertEqual(machine.state, .unlockedReady)
        XCTAssertEqual(tap.removeCount, 1)
    }

    // MARK: - Interruptions (EC-3, EC-4, EC-8)

    func testTapInterruptedTearsDown() {
        let (machine, tap, _, _, scheduler, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        tap.onTapInterrupted?() // simulate the controller's main-dispatched signal
        XCTAssertEqual(machine.state, .tearingDown)
        scheduler.fireOneShots()
        XCTAssertEqual(machine.state, .unlockedReady)
    }

    func testSystemSleepOrLockTearsDown() {
        let (machine, _, _, _, scheduler, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        machine.handle(.systemWillSleepOrLock)
        XCTAssertEqual(machine.state, .tearingDown)
        scheduler.fireOneShots()
        XCTAssertEqual(machine.state, .unlockedReady)
    }

    // MARK: - Watchdog forced unlock (FR-9c, EDGE-1)

    func testWatchdogForcedUnlockReconcilesWithoutDelay() {
        let (machine, tap, power, watchdog, _, enforcement) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        // Simulate the watchdog having already cleared enforcement off-main.
        enforcement.clearForForceStop()
        machine.handle(.watchdogForcedUnlock)
        XCTAssertEqual(machine.state, .unlockedReady) // straight to unlocked, no teardown delay
        XCTAssertEqual(tap.removeCount, 1)            // idempotent
        XCTAssertEqual(power.ended, 1)
        XCTAssertEqual(watchdog.stopped, 1)
        XCTAssertFalse(enforcement.isLocked)
    }

    // MARK: - Idempotency (FSM-3, EC-10)

    func testLockIgnoredWhileLocked() {
        let (machine, tap, _, _, _, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        machine.handle(.lockRequested) // EC-10
        XCTAssertEqual(machine.state, .locked)
        XCTAssertEqual(tap.installCount, 1)
    }

    func testUnlockIntentsIgnoredWhileUnlocked() {
        let (machine, tap, _, _, _, _) = makeMachine()
        machine.handle(.unlockRequestedByHotkey)
        machine.handle(.unlockHoldCompleted)
        machine.handle(.doubleClickUnlock)
        machine.handle(.watchdogForcedUnlock)
        XCTAssertEqual(machine.state, .unlockedReady)
        XCTAssertEqual(tap.removeCount, 0)
    }

    func testSecondHotkeyDuringDrainIsNoOp() {
        let (machine, tap, _, _, scheduler, _) = makeMachine(countdownSeconds: 0)
        machine.handle(.lockRequested)
        machine.handle(.unlockRequestedByHotkey)
        machine.handle(.unlockRequestedByHotkey) // FSM-3: no-op during drain
        XCTAssertEqual(machine.state, .unlockingDrain)
        scheduler.fireOneShots()
        scheduler.fireOneShots()
        XCTAssertEqual(machine.state, .unlockedReady)
        XCTAssertEqual(tap.removeCount, 1)
    }

    func testLockRequestRejectedWhileNeedsPermission() {
        let (machine, tap, _, _, _, _) = makeMachine(permission: .needsRelaunch)
        machine.handle(.lockRequested) // FR-4
        XCTAssertEqual(machine.state, .unlockedNeedsPermission(.needsRelaunch))
        XCTAssertEqual(tap.installCount, 0)
    }
}
