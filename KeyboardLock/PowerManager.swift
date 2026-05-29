import IOKit.pwr_mgt
import KeyboardLockCore

/// Holds an `IOPMAssertion` while locked so the display doesn't idle-sleep
/// mid-clean (EDGE-2). The assertion id is stored in `LockEnforcement` so the
/// watchdog can release it off-main on starvation (EDGE-1). `endAssertion` is
/// idempotent, which the watchdog-forced reconcile path relies on.
final class PowerManager: PowerAsserting {
    private let enforcement: LockEnforcement

    init(enforcement: LockEnforcement) {
        self.enforcement = enforcement
    }

    func beginAssertion() {
        guard enforcement.iopmAssertionID == 0 else { return } // already held
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "KeyboardLock active" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            enforcement.iopmAssertionID = id
        }
    }

    func endAssertion() {
        let id = enforcement.iopmAssertionID
        guard id != 0 else { return } // nothing held — idempotent
        IOPMAssertionRelease(id)
        enforcement.iopmAssertionID = 0
    }

    /// Off-main release used by the watchdog's forceStop action, which has
    /// already cleared the id out of `LockEnforcement` (EDGE-1). A bare
    /// `IOPMAssertionRelease` is safe to call from any thread.
    static func releaseAssertion(id: UInt32) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
    }
}
