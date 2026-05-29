import AppKit

/// Manual, mouse-driven update check (BUILD-5 / REV-4). Opens the GitHub
/// Releases page in the user's browser via `NSWorkspace.shared.open`. The app
/// itself makes ZERO network calls — the browser, a separate process the user
/// explicitly invoked, performs the fetch — keeping the "no network calls in v1"
/// privacy claim literally true (PRD §6.5 / PERM-6). No Sparkle, no appcast.
enum UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/itsBryantP/keyboard-cleaning/releases")!

    static func openReleasesPage() {
        NSWorkspace.shared.open(releasesURL)
    }
}
