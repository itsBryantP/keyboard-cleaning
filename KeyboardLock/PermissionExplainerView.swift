import SwiftUI
import KeyboardLockCore

/// First-run / remediation UI for FSM state S1 (`unlockedNeedsPermission`),
/// covering both PERM-4 variants: a genuinely missing permission, and the
/// REV-10 "granted but needs relaunch" case. Shown in place of the main window
/// content while `status != .ready` (FR-16, FR-18).
struct PermissionExplainerView: View {
    @ObservedObject var permissions: PermissionsService

    var body: some View {
        VStack(spacing: 20) {
            header

            switch permissions.status {
            case .ready:
                // Defensive: parent only shows this view while not ready.
                EmptyView()
            case let .missingPermissions(accessibility, inputMonitoring):
                missingPermissions(accessibility: accessibility, inputMonitoring: inputMonitoring)
            case .needsRelaunch:
                needsRelaunch
            }
        }
        .padding(28)
        .frame(width: 460, height: 380)
        .onAppear { permissions.startMonitoring() }
        .onDisappear { permissions.stopMonitoring() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text("Permissions needed")
                .font(.title2.bold())
            Text("KeyboardLock can’t lock the keyboard until macOS grants it the access below. It makes no network calls and reads no keystroke content.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Missing-permission variant (PERM-4 step 3)

    private func missingPermissions(accessibility: Bool, inputMonitoring: Bool) -> some View {
        VStack(spacing: 14) {
            permissionRow(
                title: "Accessibility",
                detail: "Lets KeyboardLock install the keyboard tap.",
                granted: accessibility,
                openSettings: permissions.openAccessibilitySettings
            )
            permissionRow(
                title: "Input Monitoring",
                detail: "Lets KeyboardLock see (and drop) key events.",
                granted: inputMonitoring,
                openSettings: permissions.openInputMonitoringSettings
            )

            Button("Re-check", action: permissions.refresh)
                .controlSize(.large)
                .padding(.top, 4)
                .help("Re-runs the permission check and the tap-creation probe.")
        }
        .onAppear {
            // Fire the native OS prompts once on first run; no-ops thereafter
            // (PERM-4 step 1). The deep-link buttons remain the reliable path.
            if !accessibility { permissions.requestAccessibility() }
            if !inputMonitoring { permissions.requestInputMonitoring() }
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(granted ? .green : .red)
                .accessibilityLabel(granted ? "Granted" : "Not granted")

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings", action: openSettings)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Needs-relaunch variant (REV-10 / PERM-4 step 2)

    private var needsRelaunch: some View {
        VStack(spacing: 16) {
            Text("Accessibility is granted, but macOS needs KeyboardLock to restart before it can lock the keyboard.")
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Restart Now", action: permissions.restartNow)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Button("Re-check", action: permissions.refresh)
                .help("Already restarted? Re-run the check.")
        }
    }
}
