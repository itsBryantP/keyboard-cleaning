import AppKit

/// Builds the menu-bar status images (UI-5). Unlocked is a plain `keyboard`
/// template; locked composites a `lock.fill` badge over it. Template images so
/// macOS tints them for light / dark menu bars. REV-22 snapshots these at
/// 16/32/64 pt × 1×/2× to confirm the composite stays crisp (SPEC-Q5).
enum MenuBarIcon {
    static func image(locked: Bool, pointSize: CGFloat = 18) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let base = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: locked ? "Keyboard locked" : "Keyboard active"
        )?.withSymbolConfiguration(config) ?? NSImage()

        guard locked else {
            base.isTemplate = true
            return base
        }

        let badge = NSImage(
            systemSymbolName: "lock.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize * 0.62, weight: .bold)
        ) ?? NSImage()

        let size = base.size
        let composite = NSImage(size: size)
        composite.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        let badgeSize = badge.size
        badge.draw(in: NSRect(
            x: size.width - badgeSize.width,
            y: 0,
            width: badgeSize.width,
            height: badgeSize.height
        ))
        composite.unlockFocus()
        composite.isTemplate = true
        return composite
    }
}
