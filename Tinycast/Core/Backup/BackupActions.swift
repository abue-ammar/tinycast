import AppKit
import UniformTypeIdentifiers

/// User-facing entry points for the backup flows, shared between the Settings pane and the palette commands. The Raycast decrypt runs off the main actor (scrypt is CPU-heavy); everything else is quick.
@MainActor
enum BackupActions {
    struct RaycastOutcome {
        var summary: SettingsBackup.ApplySummary
        var clipboardImported: Int
        var snippetsImported: Int
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
            let commandCount = backup.customCommands?.count ?? 0
            let shortcutCount = backup.hotkeys?.customCommands?.count ?? 0
            guard confirmExecutableImport(commands: commandCount, shortcuts: shortcutCount) else {
                return
            }
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
        // Snippet import is the only throwing step, so it runs first: a failure must not leave settings and clipboard already committed.
        let snippetsImported = try await AppCore.shared.snippetsStore.importSnippets(result.snippets).count
        let summary = result.backup.apply()
        let imported =
            result.clipboard.isEmpty
            ? 0 : AppCore.shared.clipboardStore.importEntries(result.clipboard)
        return RaycastOutcome(
            summary: summary,
            clipboardImported: imported,
            snippetsImported: snippetsImported,
            missingImages: result.missingImages)
    }

    /// Every Raycast channel (stable, beta, alpha, internal) shares this bundle-id prefix.
    static let raycastBundleIDPrefix = "com.raycast"

    static func isRaycastBundleID(_ id: String) -> Bool { id.hasPrefix(raycastBundleIDPrefix) }

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
        appliedText(s) ?? nothingImportedText
    }

    static let nothingImportedText = "Nothing to import from this file."

    /// `nil` when the backup applied no settings, so callers that also import clipboard or snippets can compose one combined sentence instead of contradicting the empty-import wording.
    static func appliedText(_ s: SettingsBackup.ApplySummary) -> String? {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        if s.customCommands > 0 { parts.append("\(s.customCommands) custom commands") }
        guard !parts.isEmpty else { return nil }
        return "Applied " + parts.joined(separator: ", ") + "."
    }

    private static func confirmExecutableImport(commands: Int, shortcuts: Int) -> Bool {
        guard commands > 0 || shortcuts > 0 else { return true }
        let commandText = commands == 1 ? "1 custom command" : "\(commands) custom commands"
        let shortcutText =
            shortcuts == 1 ? "1 global shortcut" : "\(shortcuts) global shortcuts"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Import executable commands?"
        alert.informativeText =
            "This backup contains \(commandText) and \(shortcutText). Custom commands can run "
            + "arbitrary shell code. Only import files you trust."
        alert.alertStyle = .warning
        let importButton = alert.addButton(withTitle: "Import")
        importButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
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
