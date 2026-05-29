/// What the tap callback should do after macOS disables the tap by timeout
/// (TAP-5 / REV-6). Extracted as a pure decision so it can be unit-tested in CI
/// without a real tap (the actual `CGEvent.tapEnable` call stays in the
/// app-side `LockController`).
public enum TapTimeoutOutcome: Equatable, Sendable {
    /// Keep going: the synchronous re-enable on the tap thread succeeded and we
    /// are under the consecutive-disable cap.
    case reEnableAfterTimeout
    /// Give up: re-enable failed or we tripped the cap. Collapse to
    /// `unlockedReady` with a remediation banner (EC-3).
    case interrupt
}

public enum TapPolicy {
    /// TAP-5 step 4: bound the failure at 3 consecutive disables.
    public static let consecutiveTimeoutCap = 3

    /// Decide the response to `kCGEventTapDisabledByTimeout`. `newConsecutiveCount`
    /// is the just-incremented consecutive-disable count (reset to 0 by the
    /// controller on the next clean event pass). The 10 s window from the spec is
    /// approximated by the "consecutive" reset, which is stricter and safer.
    public static func decideTapDisabledByTimeout(
        newConsecutiveCount: Int,
        reEnableSucceeded: Bool,
        cap: Int = consecutiveTimeoutCap
    ) -> TapTimeoutOutcome {
        (!reEnableSucceeded || newConsecutiveCount >= cap) ? .interrupt : .reEnableAfterTimeout
    }
}
