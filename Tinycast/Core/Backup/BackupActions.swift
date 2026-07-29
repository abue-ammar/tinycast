import AppKit
import UniformTypeIdentifiers

/// User-facing entry points for the backup flows, shared between the Settings pane and the palette commands. The Raycast decrypt runs off the main actor (scrypt is CPU-heavy); everything else is quick.
@MainActor
enum BackupActions {
    struct RaycastOutcome {
        var summary: SettingsBackup.ApplySummary
        var clipboardImported: Int
        var missingImages: Int
    }

    // MARK: - Tinycast native (self-contained: own file panels + alerts)

    static func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tinycast-Settings-\(dateStamp()).json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.gather().encoded().write(to: url, options: .atomic)
        } catch {
            present(title: "Export Failed", message: error.localizedDescription, style: .warning)
        }
    }

    static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try SettingsBackup(json: try Data(contentsOf: url))
            present(
                title: "Settings Imported", message: summaryText(backup.apply()),
                style: .informational
            )
        } catch {
            present(title: "Import Failed", message: error.localizedDescription, style: .warning)
        }
    }

    // MARK: - Raycast (the pane owns the passphrase field + inline status)

    static func importRaycast(file: URL, passphrase: String, options: RaycastImportOptions = .all)
        async throws -> RaycastOutcome
    {
        // Decrypt (scrypt/AES/gunzip) AND parse off the main actor, inside an autoreleasepool so the large JSON tree drains at once instead of spiking the main-thread footprint. Only the value-type Result crosses back.
        let result = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let decrypted = try RaycastImport.decrypt(file: file, passphrase: passphrase)
                return try RaycastImport.parse(decrypted).selecting(options)
            }
        }.value
        let summary = result.backup.apply()
        let imported =
            result.clipboard.isEmpty
            ? 0 : AppCore.shared.clipboardStore.importEntries(result.clipboard)
        return RaycastOutcome(
            summary: summary, clipboardImported: imported, missingImages: result.missingImages)
    }

    /// Every Raycast channel (stable, beta, alpha, internal) shares this bundle-id prefix.
    nonisolated static let raycastBundleIDPrefix = "com.raycast"

    nonisolated static func isRaycastBundleID(_ id: String) -> Bool {
        id.hasPrefix(raycastBundleIDPrefix)
    }

    /// Quit any running Raycast app so its hotkeys stop clashing; skip `.prohibited` (pure background helpers/XPC).
    static func quitRaycast() {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier.map(isRaycastBundleID) == true
            && app.activationPolicy != .prohibited
        {
            app.terminate()
        }
    }

    /// Shared `.rayconfig` file picker used by the Backup pane and onboarding.
    static func pickRaycastFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Helpers

    static func summaryText(_ s: SettingsBackup.ApplySummary) -> String {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        return parts.isEmpty
            ? "Nothing to import from this file." : "Applied " + parts.joined(separator: ", ") + "."
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func present(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
