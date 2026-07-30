import AppKit
// `@preconcurrency` downgrades AX concurrency diagnostics: `kAXTrustedCheckOptionPrompt` is a mutable C global but process-constant.
@preconcurrency import ApplicationServices

enum Permissions {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Preflight only — never prompts, so it is safe to poll.
    static func isInputMonitoringTrusted() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// Returns current trust state and prompts the user to grant it if needed.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Called only from the explicit Snippets opt-in gesture, after Tinycast explains why the permission is needed.
    @discardableResult
    static func requestInputMonitoringFromSnippetOptIn() -> Bool {
        CGRequestListenEventAccess()
    }

    @MainActor
    static func openAccessibilitySettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openInputMonitoringSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
