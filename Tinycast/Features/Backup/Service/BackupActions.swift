import AppKit
import UniformTypeIdentifiers

/// The backup flows' entry points, shared by the Settings pane and the commands.
@MainActor
enum BackupActions {
    struct RaycastOutcome {
        var summary: SettingsBackup.ApplySummary
        var clipboardImported: Int
        var snippetsImported: Int
        /// Set when the snippet files couldn't be written; the rest of the import still applied.
        var snippetsError: String?
        var missingImages: Int
    }

    // MARK: - Tinycast native (own file panels; dialogs come from `AppCore`)

    /// The shared save panel; an accessory app must activate first or it opens behind.
    static func chooseSaveLocation(named base: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(base)-\(dateStamp()).json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func chooseJSONFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func exportSettings(core: AppCore) async {
        guard let url = chooseSaveLocation(named: "Tinycast-Settings") else { return }
        do {
            try SettingsBackup.gather(from: core).encoded().write(to: url, options: .atomic)
        } catch {
            await present(
                core: core, title: "Export Failed", message: error.localizedDescription,
                symbol: "square.and.arrow.up")
        }
    }

    static func importSettings(core: AppCore) async {
        guard let url = chooseJSONFile() else { return }
        do {
            let backup = try SettingsBackup(json: try Data(contentsOf: url))
            let commandCount = backup.customCommands?.count ?? 0
            let shortcutCount = backup.hotkeys?.customCommands?.count ?? 0
            guard
                await confirmExecutableImport(
                    core: core, commands: commandCount, shortcuts: shortcutCount)
            else { return }
            await present(
                core: core, title: "Settings Imported",
                message: summaryText(backup.apply(to: core)),
                symbol: importSymbol, tone: .success)
        } catch {
            await present(
                core: core, title: "Import Failed", message: error.localizedDescription,
                symbol: importSymbol)
        }
    }

    // MARK: - Raycast (the pane owns the passphrase field + inline status)

    static func importRaycast(
        core: AppCore, file: URL, passphrase: String, options: RaycastImportOptions = .all
    ) async throws -> RaycastOutcome {
        // Off-main in an autoreleasepool, so the large JSON tree drains at once.
        let result = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try RaycastImport.read(file: file, passphrase: passphrase).selecting(options)
            }
        }.value
        // Reported, not thrown: it must not abort the rest of what was asked for.
        var snippetsImported = 0
        var snippetsError: String?
        if !result.snippets.isEmpty {
            do {
                // Start the store first, so imported snippets reach the launcher at once.
                if core.settings.snippetsEnabled {
                    await core.snippetsStore.start()
                }
                snippetsImported =
                    try await core.snippetsStore.importSnippets(result.snippets).count
            } catch {
                snippetsError = error.localizedDescription
            }
        }
        let summary = result.backup.apply(to: core)
        let imported =
            result.clipboard.isEmpty
            ? 0 : core.clipboardStore.importEntries(result.clipboard)
        return RaycastOutcome(
            summary: summary,
            clipboardImported: imported,
            snippetsImported: snippetsImported,
            snippetsError: snippetsError,
            missingImages: result.missingImages)
    }

    /// Every Raycast channel (stable, beta, alpha, internal) shares this bundle-id prefix.
    static let raycastBundleIDPrefix = "com.raycast"

    static func isRaycastBundleID(_ id: String) -> Bool { id.hasPrefix(raycastBundleIDPrefix) }

    /// Quit any running Raycast so its hotkeys stop clashing; background helpers stay.
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

    /// Nil when the file isn't a Raycast export; reads only the leading bytes, mapped.
    static func detectRaycastFormat(of file: URL) -> RaycastFormat? {
        guard let raw = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return try? RaycastFormat.detect(raw)
    }

    // MARK: - Helpers

    static func summaryText(_ s: SettingsBackup.ApplySummary) -> String {
        appliedText(s) ?? nothingImportedText
    }

    static let nothingImportedText = "Nothing to import from this file."

    /// nil when no settings applied, so a caller can compose one combined sentence.
    static func appliedText(_ s: SettingsBackup.ApplySummary) -> String? {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        if s.aliases > 0 { parts.append("\(s.aliases) aliases") }
        if s.customCommands > 0 { parts.append("\(s.customCommands) custom commands") }
        if s.quicklinks > 0 { parts.append("\(s.quicklinks) quicklinks") }
        guard !parts.isEmpty else { return nil }
        return "Applied " + parts.joined(separator: ", ") + "."
    }

    private static func confirmExecutableImport(
        core: AppCore, commands: Int, shortcuts: Int
    ) async
        -> Bool
    {
        guard commands > 0 || shortcuts > 0 else { return true }
        let commandText = commands == 1 ? "1 custom command" : "\(commands) custom commands"
        let shortcutText =
            shortcuts == 1 ? "1 global shortcut" : "\(shortcuts) global shortcuts"
        // Red glyph for a real warning, plain button: importing destroys nothing.
        return await core.confirm(
            title: "Import executable commands?",
            message:
                "This backup contains \(commandText) and \(shortcutText). Custom commands can run "
                + "arbitrary shell code. Only import files you trust.",
            symbol: importSymbol, confirmTitle: "Import", confirmRole: .standard)
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Every import dialog carries the same glyph, so the flow reads as one thing.
    private static let importSymbol = "square.and.arrow.down"

    private static func present(
        core: AppCore, title: String, message: String, symbol: String, tone: DialogTone = .danger
    ) async {
        await core.showNotice(title: title, message: message, symbol: symbol, tone: tone)
    }
}
