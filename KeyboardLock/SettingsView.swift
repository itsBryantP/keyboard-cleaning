import SwiftUI
import KeyboardLockCore

/// Preferences (W3, UI-6). Tabs map to PRD §5.7.
struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var stateMachine: LockStateMachine

    var body: some View {
        TabView {
            GeneralTab(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            UnlockTab(preferences: preferences, isUnlocked: stateMachine.state == .unlockedReady)
                .tabItem { Label("Unlock", systemImage: "lock") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 280)
    }
}

private struct GeneralTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $preferences.launchAtLogin)
            Toggle("Show menu bar icon", isOn: $preferences.showMenuBarItem)
            Picker("Pre-lock countdown", selection: $preferences.countdownSeconds) {
                Text("Off").tag(0)
                Text("1s").tag(1)
                Text("3s").tag(3)
                Text("5s").tag(5)
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
    }
}

private struct UnlockTab: View {
    @ObservedObject var preferences: PreferencesStore
    let isUnlocked: Bool

    var body: some View {
        Form {
            Picker("Unlock confirmation", selection: $preferences.unlockMode) {
                Text("Hold 1.5s").tag(UnlockMode.hold)
                Text("Double-click").tag(UnlockMode.doubleClick)
            }
            .pickerStyle(.radioGroup)

            LabeledContent("Unlock hotkey") {
                HStack {
                    HotkeyRecorderView(binding: $preferences.unlockHotkey, isEnabled: isUnlocked)
                        .frame(width: 140, height: 24)
                    Button("Reset to default") { preferences.resetHotkeyToDefault() }
                        .disabled(!isUnlocked)
                }
            }

            if !isUnlocked {
                Text("Unlock the keyboard to change the hotkey.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

private struct AboutTab: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("KeyboardLock").font(.title2.bold())
            Text(version).foregroundStyle(.secondary)
            Link("github.com/itsBryantP/keyboard-cleaning",
                 destination: URL(string: "https://github.com/itsBryantP/keyboard-cleaning")!)
            Button("Quit KeyboardLock") { NSApp.terminate(nil) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
