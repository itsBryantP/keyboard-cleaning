/// Pure decision for the single-instance check (ARCH-1 / REV-18) and its
/// interaction with the PERM-4 relaunch handoff (REV-NEW-1). The AppKit parts
/// (enumerating running apps, activating, terminating) live in the app target;
/// this is unit-tested in isolation.
public enum SingleInstanceDecision: Equatable, Sendable {
    /// No live sibling — this is the sole instance; carry on.
    case proceed
    /// A sibling exists but a valid relaunch-handoff marker is set: we are the
    /// intended replacement (REV-NEW-1). Survive and clear the marker; the old
    /// instance terminates itself.
    case surviveAndClearMarker
    /// A genuine double-launch (`open -n` / double click): bring the existing
    /// instance forward and terminate self so a second tap can't be installed.
    case terminateSelf

    public static func decide(hasLiveSibling: Bool, handoffValid: Bool) -> SingleInstanceDecision {
        guard hasLiveSibling else { return .proceed }
        return handoffValid ? .surviveAndClearMarker : .terminateSelf
    }
}
