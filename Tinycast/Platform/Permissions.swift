import AVFoundation
import AppKit
import EventKit
// `@preconcurrency` downgrades AX diagnostics: the option key is a constant C global.
@preconcurrency import ApplicationServices

enum Permissions {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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

    /// Full Disk Access has no prompt and no API; opening a file it guards is the only probe.
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let guarded = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            // macOS 27 has no per-user TCC.db, so only the system one can answer there.
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        return guarded.contains { path in
            let descriptor = open(path, O_RDONLY | O_CLOEXEC)
            guard descriptor >= 0 else { return false }
            close(descriptor)
            return true
        }
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func calendarAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        // Write-only is the same as nothing here: Tinycast only ever reads.
        default: return .denied
        }
    }

    /// The store is built and dropped here: a grant is process-wide, so nothing travels.
    nonisolated static func requestCalendarAccess() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    static func cameraAccess() -> CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// The one camera prompt, raised from the gesture that asked for it.
    nonisolated static func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    static func microphoneAccess() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    nonisolated static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    @MainActor
    static func openMicrophoneSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openCalendarSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
