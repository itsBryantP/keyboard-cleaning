import XCTest
import CoreGraphics
import KeyboardLockCore
@testable import KeyboardLock

/// TEST-I1 / TEST-I2 (integration). These require the test process to hold
/// Accessibility + Input Monitoring so it can both install a tap at
/// `.cghidEventTap` AND post events there (REV-13). CI cannot grant these, so
/// the whole suite self-skips unless `INTEGRATION_TESTS=1`.
///
/// Why post at `.cghidEventTap` (REV-13): posting at `.cgSessionEventTap` would
/// inject *above* the production tap, so the code under test would never see the
/// event. We post at the HID level our tap occupies and confirm the drop by a
/// separate listener installed downstream at `.cgSessionEventTap`.
final class LockControllerIntegrationTests: XCTestCase {

    private var enforcement: LockEnforcement!
    private var controller: LockController!
    private var listener: DownstreamListener!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] == "1",
            "Integration tests are local-only; set INTEGRATION_TESTS=1 with permissions granted."
        )
        enforcement = LockEnforcement()
        controller = LockController(enforcement: enforcement)
        listener = DownstreamListener()
        try XCTSkipUnless(listener.start(), "Could not install downstream listener tap — permissions?")
        try XCTSkipUnless(controller.installTap(), "Could not install HID tap — permissions?")
    }

    override func tearDownWithError() throws {
        controller?.removeTap()
        listener?.stop()
        controller = nil
        listener = nil
        enforcement = nil
    }

    /// TEST-I1: a non-hotkey key event is dropped — the downstream listener
    /// never sees it.
    func testNonHotkeyKeyIsDropped() throws {
        listener.reset()
        postKey(keyCode: 0 /* 'a' */, flags: [])    // keyDown
        postKey(keyCode: 0, flags: [], keyDown: false) // keyUp
        // Give the event pipeline a moment to deliver to any downstream tap.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(listener.sawKeyCode(0), "Suppressed key leaked to the session level")
    }

    /// TEST-I2: the configured hotkey is consumed (signals unlock) and neither
    /// its keyDown nor its keyUp tail leaks downstream.
    func testHotkeyConsumedAndTailDropped() throws {
        listener.reset()
        let unlocked = expectation(description: "unlock signalled")
        controller.onUnlockHotkey = { unlocked.fulfill() }

        let chord: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        postKey(keyCode: 37 /* 'l' */, flags: chord)               // keyDown chord
        postKey(keyCode: 37, flags: chord, keyDown: false)         // keyUp tail

        wait(for: [unlocked], timeout: 2.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(listener.sawKeyCode(37), "Unlock chord (or its tail) leaked downstream")
    }

    // MARK: - Helpers

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool = true) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

/// A listen-only tap installed downstream at `.cgSessionEventTap`, on its own
/// run-loop thread, recording the key codes it observes.
private final class DownstreamListener {
    private let seen = NSLock()
    private var keyCodes: [CGKeyCode] = []
    private var thread: Thread?
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private var started = false

    func start() -> Bool {
        let t = Thread { [weak self] in self?.run() }
        t.name = "kbl.test.downstream-listener"
        thread = t
        t.start()
        ready.wait()
        return started
    }

    private func run() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                if let refcon {
                    let me = Unmanaged<DownstreamListener>.fromOpaque(refcon).takeUnretainedValue()
                    me.record(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            started = false
            ready.signal()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let rl = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(rl, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoop = rl
        started = true
        ready.signal()
        CFRunLoopRun()
    }

    private func record(_ keyCode: CGKeyCode) {
        seen.lock(); keyCodes.append(keyCode); seen.unlock()
    }

    func sawKeyCode(_ keyCode: CGKeyCode) -> Bool {
        seen.lock(); defer { seen.unlock() }; return keyCodes.contains(keyCode)
    }

    func reset() { seen.lock(); keyCodes.removeAll(); seen.unlock() }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil; runLoop = nil; thread = nil
    }
}
