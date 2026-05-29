import SwiftUI
import KeyboardLockCore

/// SwiftUI content of the floating locked panel (UI-3). Loud, redundant cues:
/// red dot + amber-red tint + text + the hold control (AX-3). The ring fills
/// from the 60 Hz `HoldButtonModel`, not from per-tick state churn.
struct LockedPanelView: View {
    @ObservedObject var stateMachine: LockStateMachine
    @ObservedObject var preferences: PreferencesStore
    let enforcement: LockEnforcement

    @StateObject private var holdModel = HoldButtonModel()
    @State private var start = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var rearming = false
    @State private var showStuck = false
    @State private var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

    // 0.25 s tick: updates the 1 s timer label and best-effort polls the
    // transient re-arming flag (REV-6).
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            statusRow
            Text("Locked for \(formatted(elapsed))")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.secondary)

            holdControl

            (Text("Or press ")
                + Text(preferences.unlockHotkey.displayString)
                    .font(.system(.body, design: .monospaced).weight(.bold))
                + Text(" on your keyboard."))
                .font(.body)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button { showStuck = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stuck? Get help")
            }
        }
        .padding(28)
        .frame(width: 480, height: 360)
        // AX-6: deepen the tint and add an explicit border under Increase Contrast.
        .background(Color(red: 0.93, green: 0.20, blue: 0.20).opacity(increaseContrast ? 0.20 : 0.10))
        .overlay {
            if increaseContrast {
                Rectangle().strokeBorder(Color(.systemRed), lineWidth: 1)
            }
        }
        .onReceive(ticker) { _ in
            elapsed = Date().timeIntervalSince(start)
            rearming = enforcement.rearming
            increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
        .onAppear { start = Date() }
        .sheet(isPresented: $showStuck) { stuckSheet }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(.systemRed)).frame(width: 16, height: 16)
            Text("Keyboard is locked — safe to clean").font(.title3.bold())
            if rearming {
                Text("Re-arming…")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.25), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard is locked. Safe to clean.")
    }

    /// 320×96 hold control: input layer (HoldButton) under a non-hit-testing
    /// perimeter ring + label.
    private var holdControl: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color(.systemRed).opacity(0.15))

            HoldButton(
                model: holdModel,
                onBegan: { stateMachine.handle(.unlockHoldBegan) },
                onProgress: { _ in }, // ring reads holdModel.progress directly
                onCompleted: { stateMachine.handle(.unlockHoldCompleted) },
                onCancelled: { stateMachine.handle(.unlockHoldCancelled) }
            )

            RoundedRectangle(cornerRadius: 16)
                .trim(from: 0, to: holdModel.progress)
                .stroke(Color(.systemRed), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .allowsHitTesting(false)

            Text(isUnlockingDrain ? "Unlocking…" : "Hold to Unlock")
                .font(.title2.weight(.semibold))
                .allowsHitTesting(false)
        }
        .frame(width: 320, height: 96)
    }

    private var isUnlockingDrain: Bool {
        if case .unlockingDrain = stateMachine.state { return true }
        return false
    }

    private var stuckSheet: some View {
        StuckSheetView { showStuck = false }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
