import SwiftUI
import KeyboardLockCore

/// App entry point. The scene graph is fleshed out in later phases (UI-1…UI-9);
/// at this phase it routes between the first-run permission explainer (S1) and
/// a placeholder "ready" surface (S0), driven by `PermissionsService`.
@main
struct KeyboardLockApp: App {
    @StateObject private var permissions = PermissionsService()

    var body: some Scene {
        WindowGroup {
            RootView(permissions: permissions)
        }
        .windowResizability(.contentSize)
    }
}

private struct RootView: View {
    @ObservedObject var permissions: PermissionsService

    var body: some View {
        Group {
            if permissions.status.canLock {
                ReadyPlaceholderView()
            } else {
                PermissionExplainerView(permissions: permissions)
            }
        }
        // Re-check whenever the app is foregrounded, so a grant made in System
        // Settings flips us into the ready surface promptly (PERM-4 step 3).
        .onAppear { permissions.startMonitoring() }
    }
}

/// Stand-in for the full unlocked main window (UI-2), which is built in Phase 8.
private struct ReadyPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("KeyboardLock")
                .font(.largeTitle.bold())
            Text("Keyboard is active")
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 320)
    }
}
