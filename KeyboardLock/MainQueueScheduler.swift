import Foundation
import KeyboardLockCore

/// Production `LockTimerScheduling` backed by `DispatchSourceTimer`s on the main
/// queue, so the state machine's timer callbacks land on the main thread where
/// the `@MainActor` machine expects them.
final class MainQueueScheduler: LockTimerScheduling {
    final class Token: LockTimerToken {
        private var source: DispatchSourceTimer?
        init(_ source: DispatchSourceTimer) { self.source = source }
        func cancel() {
            source?.cancel()
            source = nil
        }
    }

    func scheduleOneShot(after seconds: TimeInterval, _ action: @escaping () -> Void) -> LockTimerToken {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + seconds)
        let token = Token(source)
        source.setEventHandler {
            action()
            token.cancel() // one-shot
        }
        source.resume()
        return token
    }

    func scheduleRepeating(every seconds: TimeInterval, _ action: @escaping () -> Void) -> LockTimerToken {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + seconds, repeating: seconds)
        source.setEventHandler { action() }
        source.resume()
        return Token(source)
    }
}
