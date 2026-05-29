import CoreGraphics

public extension HotkeyBinding {
    /// Human-readable chord, e.g. "⌃⌥⌘L" (UI-2, UI-3, UI-8). Modifiers in the
    /// HIG order ⌃⌥⇧⌘, followed by the key name.
    var displayString: String {
        var result = ""
        if requiredFlags.contains(.maskControl) { result += "⌃" }
        if requiredFlags.contains(.maskAlternate) { result += "⌥" }
        if requiredFlags.contains(.maskShift) { result += "⇧" }
        if requiredFlags.contains(.maskCommand) { result += "⌘" }
        result += KeyCodeNaming.displayName(for: keyCode)
        return result
    }
}

/// Maps ANSI virtual key codes to display names. v1 assumes an ANSI layout for
/// display (SPEC-Q-style simplification); unknown codes fall back to "Key N".
public enum KeyCodeNaming {
    public static func displayName(for keyCode: CGKeyCode) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let ansi = ansiKeys[keyCode] { return ansi }
        return "Key \(keyCode)"
    }

    private static let ansiKeys: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]

    private static let namedKeys: [CGKeyCode: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        115: "↖", 116: "⇞", 119: "↘", 121: "⇟", 123: "←", 124: "→", 125: "↓",
        126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
