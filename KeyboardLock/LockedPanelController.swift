import AppKit
import SwiftUI
import KeyboardLockCore

/// Manages the floating locked panel (W2, UI-3). An `NSPanel` is used for its
/// `.floating` level and `.nonactivatingPanel` style so the user's app keeps
/// key focus while they mouse around (FR-14).
///
/// REV-17 fallback: if the non-activating panel fails to route mouse events to
/// the HoldButton on device, swap the panel for a regular `NSWindow` at
/// `.floating` level with `canBecomeKey` overridden to `false`. That change is
/// localized here and to `HoldButtonControl.acceptsFirstMouse`.
@MainActor
final class LockedPanelController {
    private let stateMachine: LockStateMachine
    private let preferences: PreferencesStore
    private let enforcement: LockEnforcement
    private var panel: NSPanel?

    init(stateMachine: LockStateMachine, preferences: PreferencesStore, enforcement: LockEnforcement) {
        self.stateMachine = stateMachine
        self.preferences = preferences
        self.enforcement = enforcement
    }

    func show() {
        let panel = panel ?? makePanel()
        positionOnCursorScreen(panel)
        // orderFrontRegardless keeps the user's app key (non-activating).
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// REV-2: the menu bar "Unlock Keyboard" item routes here rather than
    /// unlocking directly — surface the panel and draw the eye to the hold
    /// control (the actual unlock still requires the FR-7 hold).
    func surfaceForUnlock() {
        show()
        panel?.contentView?.layer?.removeAllAnimations()
        // A single pulse is added with the menu bar work in Phase 10.
    }

    private func makePanel() -> NSPanel {
        let content = LockedPanelView(
            stateMachine: stateMachine,
            preferences: preferences,
            enforcement: enforcement
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "KeyboardLock"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false // movable by title bar only
        panel.contentView = NSHostingView(rootView: content)
        panel.setFrameAutosaveName("KeyboardLockLockedPanel")
        self.panel = panel
        return panel
    }

    /// EDGE-3: center on the screen containing the cursor at lock time.
    private func positionOnCursorScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
