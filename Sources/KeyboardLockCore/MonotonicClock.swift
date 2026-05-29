import Foundation

/// Minimal monotonic clock seam (REV-5). Injected into the `Watchdog` so
/// TEST-U5 can drive a synthetic stall with a fake clock and assert the
/// starvation path fires exactly once — the production and test code paths are
/// then identical.
public protocol MonotonicClock: Sendable {
    /// Seconds on a monotonic timeline (never goes backwards, unaffected by wall
    /// clock changes).
    func now() -> Double
}

/// Production clock backed by the monotonic uptime counter. Crucially it keeps
/// advancing while the main thread is stalled, which is exactly the condition
/// the watchdog exists to catch (EDGE-1 / TEST-M6).
public struct SystemMonotonicClock: MonotonicClock {
    public init() {}
    public func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

public extension Notification.Name {
    /// Posted by the watchdog after it force-restores the keyboard off-main
    /// (EDGE-1). The `@MainActor` state machine observes it and reconciles the
    /// UI when main next runs (REV-11).
    static let kbStateForcedUnlocked = Notification.Name("com.itsbryantp.keyboardlock.stateForcedUnlocked")
}
