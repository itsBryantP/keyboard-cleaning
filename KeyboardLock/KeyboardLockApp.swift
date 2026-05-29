import SwiftUI
import KeyboardLockCore

/// App entry point. Owns the runtime object graph (`AppEnvironment`) and hosts
/// the main window (W1). The floating locked panel (W2), menu bar item (M1),
/// and Settings scene (W3) are added in later phases.
@main
struct KeyboardLockApp: App {
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
