import AppKit
import KeyboardLockCore

/// Enforces single-instance at launch (ARCH-1 / REV-18) and manages the
/// relaunch-handoff marker (REV-NEW-1). The decision is the pure
/// `SingleInstanceDecision`; this type supplies the AppKit facts and effects.
@MainActor
enum SingleInstanceCoordinator {
    static let handoffKey = "relaunchHandoffUntil"
    private static let handoffWindow: TimeInterval = 3

    /// Run from `applicationDidFinishLaunching`. Terminates this instance if a
    /// genuine duplicate is already running.
    static func enforceOnLaunch(defaults: UserDefaults = .standard, now: Date = Date()) {
        let me = NSRunningApplication.current
        let bundleID = Bundle.main.bundleIdentifier

        let hasLiveSibling = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleID
                && app.processIdentifier != me.processIdentifier
                && !app.isTerminated
        }
        let handoffValid = (defaults.object(forKey: handoffKey) as? Date).map { $0 > now } ?? false

        switch SingleInstanceDecision.decide(hasLiveSibling: hasLiveSibling, handoffValid: handoffValid) {
        case .proceed:
            break
        case .surviveAndClearMarker:
            defaults.removeObject(forKey: handoffKey)
        case .terminateSelf:
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == bundleID && $0.processIdentifier != me.processIdentifier }?
                .activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }

    /// Called by the old instance just before launching its replacement so the
    /// fresh instance survives the single-instance check (REV-NEW-1).
    static func beginRelaunchHandoff(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(now.addingTimeInterval(handoffWindow), forKey: handoffKey)
    }
}
