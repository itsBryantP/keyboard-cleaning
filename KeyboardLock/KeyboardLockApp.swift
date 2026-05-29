import SwiftUI
import KeyboardLockCore

/// App entry point. The scene graph is fleshed out in later phases (UI-1…UI-9);
/// for the scaffold it is a single placeholder window proving the app target
/// links `KeyboardLockCore` and launches.
@main
struct KeyboardLockApp: App {
    var body: some Scene {
        WindowGroup {
            ScaffoldView()
        }
        .windowResizability(.contentSize)
    }
}

private struct ScaffoldView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
            Text("KeyboardLock")
                .font(.largeTitle.bold())
            Text("Scaffold — core \(KeyboardLockCore.scaffoldVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 320)
    }
}
