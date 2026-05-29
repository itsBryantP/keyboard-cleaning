import AppKit
import SwiftUI

/// 60 Hz progress source for the hold gesture, surfaced to SwiftUI so the ring
/// can fill smoothly without spamming the state machine (FSM-5 step 1).
final class HoldButtonModel: ObservableObject {
    @Published var progress: Double = 0
}

/// The committed hold-to-unlock control (FSM-5 / REV-8): a custom `NSControl`
/// that owns the press lifecycle and a ~60 Hz progress driver. SwiftUI gestures
/// were rejected (no intermediate progress, hit-testing conflicts), so this is
/// the single design.
///
/// REV-17 — non-activating panel mouse routing: `acceptsFirstMouse` returns
/// `true` so the very first click inside the floating, non-activating panel
/// begins the hold without first activating the app (the user's app keeps key
/// focus). This is the riskiest interaction in the app and MUST be verified
/// manually (a TEST-M pass) on device. If press/drag/release does not fire here
/// while another app holds focus, fall back to a regular `NSWindow` at
/// `.floating` level with `canBecomeKey` overridden to `false` (see UI-3 /
/// REV-17) — that change is isolated to `LockedPanelController`.
final class HoldButtonControl: NSControl {
    weak var model: HoldButtonModel?
    var onBegan: (() -> Void)?
    var onProgress: ((Double) -> Void)?
    var onCompleted: (() -> Void)?
    var onCancelled: (() -> Void)?

    /// FR-7a hold duration.
    var holdDuration: TimeInterval = 1.5
    /// REV-8 cursor-exit hysteresis margin.
    var exitInset: CGFloat = 8

    private var driver: DispatchSourceTimer?
    private var startUptime: Double = 0
    private var isPressing = false

    override var acceptsFirstResponder: Bool { true }

    /// Crucial for the non-activating panel (REV-17): register the first click
    /// even though the panel isn't key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginHold()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressing else { return }
        // REV-8: cancel (never complete) once the cursor leaves the inset
        // bounds — a cleaning cloth dragging off must cancel.
        let point = convert(event.locationInWindow, from: nil)
        if !bounds.insetBy(dx: exitInset, dy: exitInset).contains(point) {
            cancelHold()
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Early release before completion → cancel (stays locked).
        if isPressing { cancelHold() }
    }

    override func mouseExited(with event: NSEvent) {
        if isPressing { cancelHold() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // Window resign / teardown: never leave a hold running (FSM-5 step 6).
        if newWindow == nil, isPressing { cancelHold() }
    }

    // MARK: - Drive

    private func beginHold() {
        guard !isPressing else { return }
        isPressing = true
        startUptime = Self.now()
        setProgress(0)
        onBegan?()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16)) // ~60 Hz
        timer.setEventHandler { [weak self] in self?.tick() }
        driver = timer
        timer.resume()
    }

    private func tick() {
        guard isPressing else { return }
        let elapsed = Self.now() - startUptime
        let p = min(max(elapsed / holdDuration, 0), 1)
        setProgress(p)
        onProgress?(p)
        if p >= 1 { complete() }
    }

    private func complete() {
        stopDriver()
        isPressing = false
        onCompleted?()
    }

    private func cancelHold() {
        stopDriver()
        isPressing = false
        setProgress(0)
        onCancelled?()
    }

    private func stopDriver() {
        driver?.cancel()
        driver = nil
    }

    private func setProgress(_ value: Double) {
        model?.progress = value
    }

    private static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

/// SwiftUI wrapper for the hold control. The visible ring is drawn in SwiftUI
/// from `model.progress`; this representable is the input layer beneath it.
struct HoldButton: NSViewRepresentable {
    @ObservedObject var model: HoldButtonModel
    var onBegan: () -> Void
    var onProgress: (Double) -> Void
    var onCompleted: () -> Void
    var onCancelled: () -> Void

    func makeNSView(context: Context) -> HoldButtonControl {
        let control = HoldButtonControl()
        control.model = model
        apply(to: control)
        // AX-1 / AX-7: a labelled button element so VoiceOver describes it and
        // Voice/Switch Control can target it. A single "Click" press-releases
        // (cancels, staying locked); "Press and hold" completes — matching the
        // FR-7 safeguard with no single-action unlock.
        control.setAccessibilityElement(true)
        control.setAccessibilityRole(.button)
        control.setAccessibilityLabel("Hold to unlock")
        control.setAccessibilityHelp("Press and hold for one and a half seconds to unlock the keyboard.")
        return control
    }

    func updateNSView(_ control: HoldButtonControl, context: Context) {
        control.model = model
        apply(to: control)
    }

    private func apply(to control: HoldButtonControl) {
        control.onBegan = onBegan
        control.onProgress = onProgress
        control.onCompleted = onCompleted
        control.onCancelled = onCancelled
    }
}
