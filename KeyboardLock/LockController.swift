import AppKit
import Combine
import CoreGraphics
import KeyboardLockCore
import os

/// Owns the `CGEventTap` and runs its `CFRunLoop` on a dedicated POSIX thread
/// (ARCH-2, TAP-1). Makes the allow/deny decision per keystroke and signals the
/// main thread when the unlock chord is matched or the tap is interrupted.
///
/// The callback runs on the tap thread and touches only `LockEnforcement` and
/// `DispatchQueue.main.async` — never SwiftUI / `@Published` (ARCH-4). Lives in
/// the app target (not the core package) because TAP-3 step 2 needs
/// `NSEvent(cgEvent:)` to distinguish media-key `systemDefined` events.
final class LockController: LockTapControlling {
    /// Tap thread → main signals. Set once before `installTap()`; the caller
    /// (LockStateMachine) marshals these onto the main actor.
    var onUnlockHotkey: (() -> Void)?
    var onTapInterrupted: (() -> Void)?

    private let enforcement: LockEnforcement

    /// Live tap handles, set once on the tap thread after creation and read by
    /// both main (`removeTap`) and the watchdog queue (`forceStopFromWatchdog`).
    /// Guarding them in one lock makes teardown atomic and double-call-safe.
    private struct TapResources: @unchecked Sendable {
        let tap: CFMachPort
        let source: CFRunLoopSource
        let runLoop: CFRunLoop
    }
    private let resources = OSAllocatedUnfairLock<TapResources?>(initialState: nil)

    private var tapThread: Thread?
    private let installResult = DispatchSemaphore(value: 0)
    private var installSucceeded = false

    /// REV-9: binding updates are delivered on a dedicated serial queue, never
    /// on the tap's hot path.
    private let bindingQueue = DispatchQueue(label: "com.itsbryantp.keyboardlock.binding")
    private var bindingCancellable: AnyCancellable?

    init(enforcement: LockEnforcement) {
        self.enforcement = enforcement
    }

    // MARK: - Preference binding (TAP-6 / REV-9)

    /// Subscribe to unlock-hotkey changes. The single direction is
    /// `Prefs → (Combine) → LockController → LockEnforcement`; `PreferencesStore`
    /// never references the controller.
    @MainActor
    func bindUnlockHotkey(from preferences: PreferencesStore) {
        enforcement.binding = preferences.unlockHotkey // initial value, synchronously
        bindingCancellable = preferences.$unlockHotkey
            .receive(on: bindingQueue)
            .sink { [weak self] binding in self?.applyBindingIfUnlocked(binding) }
    }

    private func applyBindingIfUnlocked(_ binding: HotkeyBinding) {
        // FR-8a: a binding change must never land mid-lock. The recorder is only
        // interactive while unlocked, so this guard is belt-and-suspenders.
        guard enforcement.isUnlockedMirror else {
            #if DEBUG
            assertionFailure("Unlock hotkey changed while not unlocked (FR-8a)")
            #endif
            return
        }
        enforcement.binding = binding
    }

    // MARK: - Install / remove (main thread)

    /// Spins up the tap thread, creates + enables the tap, and blocks until the
    /// outcome is known. Returns whether the tap is live. Must be called only
    /// after permissions are granted and the REV-10 probe passed.
    @discardableResult
    func installTap() -> Bool {
        guard tapThread == nil else { return enforcement.tapInstalled }

        installSucceeded = false
        let thread = Thread { [weak self] in self?.runTapThread() }
        thread.name = "com.itsbryantp.keyboardlock.tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        installResult.wait()

        if !installSucceeded { tapThread = nil }
        return installSucceeded
    }

    /// Normal teardown from the main thread (FSM `tearingDown`).
    func removeTap() {
        teardownTapResources()
        tapThread = nil
    }

    /// Watchdog starvation path (EDGE-1): tear the tap down from the watchdog
    /// queue using only documented-thread-safe CF calls (SPEC-A5). Safe to race
    /// with `removeTap` — the lock ensures exactly one teardown runs.
    func forceStopFromWatchdog() {
        teardownTapResources()
    }

    // MARK: - Tap thread body

    private func runTapThread() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: TapConfiguration.tapLocation,
            place: TapConfiguration.tapPlacement,
            options: .defaultTap, // active tap that can drop events (FR-3)
            eventsOfInterest: TapConfiguration.lockedEventMask,
            callback: lockTapCallback,
            userInfo: refcon
        ) else {
            installSucceeded = false
            installResult.signal()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            installSucceeded = false
            installResult.signal()
            return
        }
        let runLoop = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        resources.withLock { $0 = TapResources(tap: tap, source: source, runLoop: runLoop) }
        enforcement.tapInstalled = true
        enforcement.resetTapTimeouts()
        installSucceeded = true
        installResult.signal()

        // Blocks until CFRunLoopStop is called during teardown.
        CFRunLoopRun()
    }

    private func teardownTapResources() {
        // Atomically take and clear the handles so only the first caller acts.
        let res = resources.withLock { current -> TapResources? in
            let value = current
            current = nil
            return value
        }
        guard let res else { return }
        CGEvent.tapEnable(tap: res.tap, enable: false)
        CFRunLoopSourceInvalidate(res.source)
        CFMachPortInvalidate(res.tap)
        CFRunLoopStop(res.runLoop)
        enforcement.tapInstalled = false
    }

    // MARK: - Callback handling (tap thread)

    /// Entry point from the C trampoline. Returns the event (passthrough), or
    /// nil to drop / consume.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // systemDefined (NX_SYSDEFINED) is not a named CGEventType case (TAP-3
        // step 2): match it by raw value and drop only media-key subtypes.
        if type.rawValue == TapConfiguration.systemDefinedEventTypeRawValue {
            if isMediaKeySystemDefined(event) {
                clearRearmOnCleanPass()
                return nil // drop media / brightness keys while locked
            }
            return Unmanaged.passUnretained(event) // pass through other system events
        }

        switch type {
        case .tapDisabledByTimeout:
            return handleTimeout()

        case .tapDisabledByUserInput:
            // e.g. Accessibility revoked mid-session — do not re-enable (TAP-5).
            signalInterrupted()
            return nil

        case .keyDown, .keyUp, .flagsChanged:
            // Only a keyDown can complete the unlock chord; matching keyUp too
            // would fire a second unlock from the chord's release.
            if type == .keyDown {
                let keyEvent = KeyEvent(
                    keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
                    flags: event.flags
                )
                if HotkeyMatcher.matches(keyEvent, against: enforcement.binding) {
                    signalUnlock()
                    clearRearmOnCleanPass()
                    return nil // consume the chord (TAP-3 step 3)
                }
            }
            clearRearmOnCleanPass()
            return nil // blanket suppression (FR-3, FR-5, FR-6)

        default:
            return nil
        }
    }

    private func handleTimeout() -> Unmanaged<CGEvent>? {
        let count = enforcement.recordTapTimeout()
        enforcement.rearming = true // REV-6: surface the "Re-arming…" pill

        var reEnabled = false
        if let res = resources.withLock({ $0 }) {
            // Tightest possible loop: re-enable synchronously on this thread.
            CGEvent.tapEnable(tap: res.tap, enable: true)
            reEnabled = CGEvent.tapIsEnabled(tap: res.tap)
        }

        if TapPolicy.decideTapDisabledByTimeout(
            newConsecutiveCount: count,
            reEnableSucceeded: reEnabled
        ) == .interrupt {
            signalInterrupted()
        }
        return nil // the disabling event itself is dropped
    }

    /// TAP-5 step 3: a clean event pass means we recovered — clear the pill and
    /// the consecutive-disable counter.
    private func clearRearmOnCleanPass() {
        if enforcement.rearming { enforcement.rearming = false }
        if enforcement.consecutiveTapTimeouts != 0 { enforcement.resetTapTimeouts() }
    }

    private func isMediaKeySystemDefined(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined else {
            return false
        }
        // subtype 8 == NX_SUBTYPE_AUX_CONTROL_BUTTONS (media / brightness keys).
        return nsEvent.subtype.rawValue == 8
    }

    private func signalUnlock() {
        DispatchQueue.main.async { [weak self] in self?.onUnlockHotkey?() }
    }

    private func signalInterrupted() {
        DispatchQueue.main.async { [weak self] in self?.onTapInterrupted?() }
    }
}

/// C function pointer for `CGEvent.tapCreate` (TAP-3). A top-level function with
/// no captures so it bridges to a C callback; the controller is recovered from
/// `refcon`.
private func lockTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<LockController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
