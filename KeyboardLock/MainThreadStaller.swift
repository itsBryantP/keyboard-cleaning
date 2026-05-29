#if DEBUG
import Foundation

/// DEBUG-only harness for TEST-M6 (REV-5): genuinely starve the main thread with
/// a busy-wait so other threads — the watchdog's `DispatchSourceTimer` and the
/// tap thread — keep running. This is the only way to exercise the production
/// starvation path. Compiled out of release builds; wired to a "Stall main
/// thread (6 s)" menu item in Phase 10.
///
/// Do NOT use `lldb` + `process interrupt` to simulate this (REV-5): that halts
/// *all* threads including the watchdog, and `ContinuousClock` advancing across
/// the debugger pause makes the check pass for the wrong reason.
enum MainThreadStaller {
    static func stall(seconds: TimeInterval = 6.0) {
        assert(Thread.isMainThread, "The stall harness must run on the main thread to be meaningful.")
        let deadline = CFAbsoluteTimeGetCurrent() + seconds
        while CFAbsoluteTimeGetCurrent() < deadline {}
    }
}
#endif
