import AppKit
// `@preconcurrency` downgrades AX concurrency diagnostics: `kAXTrustedCheckOptionPrompt` is a mutable C global but process-constant.
@preconcurrency import ApplicationServices

enum Permissions {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func isInputMonitoringTrusted() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func isFullyTrusted() -> Bool {
        isAccessibilityTrusted() && isInputMonitoringTrusted()
    }

    /// Returns current trust state and prompts the user to grant it if needed.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Explicitly prompts the user to grant Input Monitoring access in System Settings if needed.
    @discardableResult
    static func requestInputMonitoringPrompt() -> Bool {
        CGRequestListenEventAccess()
    }

    @MainActor
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
