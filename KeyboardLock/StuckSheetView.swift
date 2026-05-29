import SwiftUI

/// "Stuck?" help sheet (UI-9). Mouse-only Force Quit guidance. Deliberately does
/// NOT bind or suggest ⌥⌘Esc: while locked our tap consumes it before the OS
/// sees it, so the keyboard Force Quit shortcut is unavailable (FR-9a / REV-7).
/// The supported escape is the Apple-menu flow, which the mouse can always reach.
struct StuckSheetView: View {
    let onClose: () -> Void

    private let steps = [
        "Click the Apple menu  in the top-left corner of the screen.",
        "Choose “Force Quit…”.",
        "Select the app that stopped responding, then click Force Quit.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App stopped responding?")
                .font(.title2.bold())

            Text("The keyboard is locked, but your mouse still works. Quit a frozen app from the Apple menu:")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).").bold().frame(width: 18, alignment: .trailing)
                        Text(step).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Label(
                "The keyboard Force Quit shortcut (⌥⌘Esc) is unavailable while locked. Use the Apple menu above with your mouse.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Close", action: onClose) // single click; just a help sheet
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}
