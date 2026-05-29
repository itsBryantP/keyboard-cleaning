import Foundation
import Combine
import CoreGraphics

/// UserDefaults-backed persisted preferences (DATA-1). `hasCompletedFirstRun` is
/// intentionally absent (REV-15) — the first-run UI is driven entirely by live
/// permission state + the tap probe.
///
/// Lives in the core package so TEST-U3 round-trips it via `swift test`.
/// `unlockHotkey` is the producer end of the REV-9 binding-update flow: the
/// controller subscribes to `$unlockHotkey`. Launch-at-login registration
/// (SMAppService) is handled app-side, reacting to `launchAtLogin`.
@MainActor
public final class PreferencesStore: ObservableObject, LockPreferencesProviding {
    private enum Keys {
        static let countdown = "prefs.countdownSeconds"
        static let unlockMode = "prefs.unlockMode"
        static let hotkeyKeyCode = "prefs.unlockHotkey.keyCode"
        static let hotkeyFlags = "prefs.unlockHotkey.flags"
        static let launchAtLogin = "prefs.launchAtLogin"
        static let showMenuBarItem = "prefs.showMenuBarItem"
    }

    /// Allowed countdown values (UI-6 segmented control); default 3 (D-2).
    public static let allowedCountdowns = [0, 1, 3, 5]

    private let defaults: UserDefaults

    @Published public var countdownSeconds: Int {
        didSet { defaults.set(countdownSeconds, forKey: Keys.countdown) }
    }
    @Published public var unlockMode: UnlockMode {
        didSet { defaults.set(unlockMode.rawValue, forKey: Keys.unlockMode) }
    }
    @Published public var unlockHotkey: HotkeyBinding {
        didSet {
            defaults.set(Int(unlockHotkey.keyCode), forKey: Keys.hotkeyKeyCode)
            defaults.set(unlockHotkey.flagsRawValue, forKey: Keys.hotkeyFlags)
        }
    }
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published public var showMenuBarItem: Bool {
        didSet { defaults.set(showMenuBarItem, forKey: Keys.showMenuBarItem) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedCountdown = defaults.object(forKey: Keys.countdown) as? Int
        countdownSeconds = PreferencesStore.allowedCountdowns.contains(storedCountdown ?? 3)
            ? (storedCountdown ?? 3) : 3

        let storedMode = defaults.string(forKey: Keys.unlockMode)
        unlockMode = storedMode.flatMap(UnlockMode.init(rawValue:)) ?? .hold

        let keyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
        let flags = defaults.object(forKey: Keys.hotkeyFlags) as? UInt64
        if let keyCode, let flags {
            let restored = HotkeyBinding(keyCode: CGKeyCode(keyCode), flagsRawValue: flags)
            // A persisted modifier-less chord is invalid (FR-8b) — fall back.
            unlockHotkey = restored.hasRequiredModifier ? restored : .defaultUnlock
        } else {
            unlockHotkey = .defaultUnlock
        }

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin) // default false
        showMenuBarItem = (defaults.object(forKey: Keys.showMenuBarItem) as? Bool) ?? true

        // Reset to default ⌃⌥⌘L (UI-6 "Reset to default" button helper, D-4).
    }

    public func resetHotkeyToDefault() {
        unlockHotkey = .defaultUnlock
    }
}
