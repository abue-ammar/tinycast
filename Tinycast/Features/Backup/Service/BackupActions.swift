import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// Not per-channel: a UTI names an interchange format, so Dev must read stable's exports.
    static let tinycastBackup = UTType(exportedAs: "com.tinycast.backup")
}

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
    static func chooseSaveLocation(named base: String, type: UTType = .json) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let ext = type.preferredFilenameExtension ?? "json"
        panel.nameFieldStringValue = "\(base)-\(dateStamp()).\(ext)"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func chooseJSONFile() -> URL? { chooseFile(ofType: .json) }

    static func chooseBackupFile() -> URL? { chooseFile(ofType: .tinycastBackup) }

    private static func chooseFile(ofType type: UTType) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Tinycast backups

    /// Composes off-main, then seals — a clipboard history runs to gigabytes.
    static func exportBackup(
        core: AppCore, categories: Set<BackupCategory>
    ) async throws
        -> BackupComposer.Result
    {
        guard let destination = chooseSaveLocation(named: "Tinycast", type: .tinycastBackup) else {
            throw CancellationError()
        }
        let plan = BackupComposer.plan(categories, from: core)
        return try await Task.detached(priority: .userInitiated) {
            let staging = try BackupStaging()
            defer { staging.discard() }
            let result = try BackupComposer.write(plan, into: staging.bundle)
            try BackupArchive.seal(directory: staging.root, into: destination)
            return result
        }.value
    }

    /// Opens the archive and reads its manifest, leaving staging for the caller to apply and discard.
    static func openBackup(at file: URL) async throws -> (BackupStaging, BackupManifest) {
        try await Task.detached(priority: .userInitiated) {
            let staging = try BackupStaging()
            do {
                try BackupArchive.open(file: file, into: staging.root)
                return (staging, try staging.bundle.readManifest())
            } catch {
                staging.discard()
                throw error
            }
        }.value
    }

    static func applyBackup(
        _ categories: Set<BackupCategory>, from staging: BackupStaging, to core: AppCore
    ) async -> BackupApplier.Summary? {
        let bundle = staging.bundle
        if categories.contains(.configuration),
            let data = try? Data(contentsOf: bundle.settingsURL),
            let backup = try? SettingsBackup(json: data)
        {
            let commands = backup.customCommands?.count ?? 0
            let shortcuts = backup.hotkeys?.customCommands?.count ?? 0
            guard await confirmExecutableImport(core: core, commands: commands, shortcuts: shortcuts)
            else { return nil }
        }
        return await BackupApplier.apply(categories, from: bundle, to: core)
    }

    /// The launcher has no picker, so its commands take everything; the pane is where you choose.
    static func runExportCommand(core: AppCore) async {
        do {
            let result = try await exportBackup(core: core, categories: BackupCategory.all)
            await present(
                core: core, title: "Backup Exported", message: exportText(result),
                symbol: exportSymbol, tone: .success)
        } catch is CancellationError {
        } catch {
            await present(
                core: core, title: "Export Failed", message: error.localizedDescription,
                symbol: exportSymbol)
        }
    }

    static func runImportCommand(core: AppCore) async {
        guard let file = chooseBackupFile() else { return }
        do {
            let (staging, manifest) = try await openBackup(at: file)
            defer { staging.discard() }
            guard
                let summary = await applyBackup(manifest.categories, from: staging, to: core)
            else { return }
            await present(
                core: core, title: "Backup Imported", message: summaryText(summary),
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
                try RaycastImportReader.read(file: file, passphrase: passphrase).selecting(options)
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

    /// Reads only the leading bytes, mapped, so a file is labelled before a passphrase is typed.
    static func isRaycastExport(_ file: URL) -> Bool {
        guard let raw = try? Data(contentsOf: file, options: .mappedIfSafe) else { return false }
        return RaycastDecoder.isExport(raw)
    }

    // MARK: - Helpers

    static func summaryText(_ s: SettingsBackup.ApplySummary) -> String {
        appliedText(s) ?? nothingImportedText
    }

    /// One sentence per category that actually moved, so an import is never silent.
    static func summaryText(_ summary: BackupApplier.Summary) -> String {
        var parts: [String] = []
        if let settings = summary.settings, let applied = appliedText(settings) {
            parts.append(applied)
        }
        var imported: [String] = []
        if summary.clipboard > 0 { imported.append("\(summary.clipboard) clips") }
        if summary.snippets > 0 { imported.append("\(summary.snippets) snippets") }
        if summary.notes > 0 { imported.append("\(summary.notes) notes") }
        if summary.learning > 0 { imported.append("\(summary.learning) learning records") }
        if !imported.isEmpty {
            parts.append("Imported " + imported.joined(separator: ", ") + ".")
        }
        parts.append(contentsOf: summary.problems)
        return parts.isEmpty ? nothingImportedText : parts.joined(separator: " ")
    }

    static func exportText(_ result: BackupComposer.Result) -> String {
        let categories = BackupCategory.ordered(result.manifest.categories)
        var text =
            categories.isEmpty
            ? "Nothing was selected."
            : "Saved "
                + categories.map(\.descriptor.label)
                .joined(separator: ", ") + "."
        if result.missingImages > 0 {
            text += " \(result.missingImages) images were unavailable and skipped."
        }
        return text
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
        if s.actionChains > 0 { parts.append("\(s.actionChains) action chains") }
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
    private static let exportSymbol = "square.and.arrow.up"

    private static func present(
        core: AppCore, title: String, message: String, symbol: String, tone: DialogTone = .danger
    ) async {
        await core.showNotice(title: title, message: message, symbol: symbol, tone: tone)
    }
}
