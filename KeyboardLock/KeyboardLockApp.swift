import SwiftUI
import KeyboardLockCore

/// App entry point. Owns the runtime object graph (`AppEnvironment`) and hosts
/// the main window (W1). The floating locked panel (W2), menu bar item (M1),
/// and Settings scene (W3) are added in later phases.
/// Runs the single-instance check at launch (ARCH-1 / REV-18) before the rest
/// of the app spins up.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstanceCoordinator.enforceOnLaunch()
    }
}

@main
struct KeyboardLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(
                stateMachine: env.stateMachine,
                permissions: env.permissions,
                preferences: env.preferences
            )
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(preferences: env.preferences, stateMachine: env.stateMachine)
        }
    }
}
