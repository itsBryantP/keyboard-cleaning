import Carbon

/// Wraps `IsSecureEventInputEnabled()` (L-1). When another app has Secure Input
/// active (e.g. a focused password field), our tap cannot see those keystrokes,
/// so we warn before locking (UI-9) rather than silently failing to suppress.
enum SecureInput {
    static var isActive: Bool { IsSecureEventInputEnabled() }
}
