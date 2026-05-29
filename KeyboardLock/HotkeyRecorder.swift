import AppKit
import SwiftUI
import KeyboardLockCore

/// Records a chord into a `HotkeyBinding` (UI-8, FR-8a/FR-8b). An `NSButton`
/// that, while recording, installs a local event monitor and captures the first
/// `keyDown` carrying at least one ⇧⌃⌥⌘ modifier. `fn` is stripped (REV-12) and
/// modifier-less chords are rejected. Disabled unless the keyboard is unlocked
/// (FR-8a).
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var binding: HotkeyBinding
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: binding.displayString, target: context.coordinator, action: #selector(Coordinator.toggle))
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = isEnabled
        if !context.coordinator.isRecording {
            button.title = binding.displayString
        }
        if !isEnabled { context.coordinator.stop() } // can't record while locked
    }

    final class Coordinator: NSObject {
        var parent: HotkeyRecorderView
        weak var button: NSButton?
        private var monitor: Any?
        private(set) var isRecording = false

        /// Chords the local monitor can't reliably capture or shouldn't bind.
        private static let deniedWithCommand: Set<CGKeyCode> = [48 /* Tab: ⌘⇥ */]

        init(_ parent: HotkeyRecorderView) { self.parent = parent }

        @objc func toggle() {
            isRecording ? stop() : start()
        }

        private func start() {
            guard !isRecording else { return }
            isRecording = true
            button?.title = "Press shortcut…"
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stop() {
            guard isRecording else { return }
            isRecording = false
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            button?.title = parent.binding.displayString
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.type == .keyDown else { return nil } // swallow flagsChanged too
            let flags = Self.cgFlags(from: event.modifierFlags)
            let keyCode = CGKeyCode(event.keyCode)

            if Self.deniedWithCommand.contains(keyCode), flags.contains(.maskCommand) {
                button?.title = "Reserved by macOS"
                return nil
            }
            if let candidate = HotkeyBinding.validated(keyCode: keyCode, flags: flags) {
                parent.binding = candidate
                stop()
            } else {
                button?.title = "Modifiers required" // FR-8b
            }
            return nil // swallow the recorded event
        }

        private static func cgFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
            var flags: CGEventFlags = []
            if modifiers.contains(.control) { flags.insert(.maskControl) }
            if modifiers.contains(.option) { flags.insert(.maskAlternate) }
            if modifiers.contains(.shift) { flags.insert(.maskShift) }
            if modifiers.contains(.command) { flags.insert(.maskCommand) }
            // fn deliberately omitted (REV-12); normalization strips it anyway.
            return flags
        }
    }
}
