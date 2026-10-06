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
        var snippetsNeedEnabling: Bool
        /// Set when the snippet files couldn't be written; the rest of the import still applied.
        var snippetsError: String?
        var quicklinksImported: Int
        /// Set when the library wouldn't open; the rest of the import still applied.
        var quicklinksError: String?
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
        var quicklinksImported = 0
        var quicklinksError: String?
        if !result.quicklinks.isEmpty {
            if core.quicklinks.isAvailable {
                quicklinksImported =
                    core.quicklinkCoordinator.addImportedQuicklinks(result.quicklinks).added.count
                // Opening a link grants no permission class, so landing a library turns the switch on.
                if quicklinksImported > 0 { core.settings.quicklinksEnabled = true }
            } else {
                quicklinksError = QuicklinkError.storageUnavailable.errorDescription
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
            snippetsNeedEnabling: snippetsImported > 0 && !core.settings.snippetsEnabled,
            snippetsError: snippetsError,
            quicklinksImported: quicklinksImported,
            quicklinksError: quicklinksError,
            missingImages: result.missingImages)
    }

    // MARK: - Alfred (an unencrypted package folder; the pane owns the inline status)

    struct AlfredOutcome {
        var settingsFields: Int
        var shortcuts: Int
        var snippetsImported: Int
        var snippetsNeedEnabling: Bool
        /// Set when the snippet files couldn't be written; the rest of the import still applied.
        var snippetsError: String?
        var quicklinksImported: Int
        var quicklinksKeywordsUpdated: Int
        /// Set when the library wouldn't open; the rest of the import still applied.
        var quicklinksError: String?
        var commandsImported: Int
        var skippedWorkflows: Int
        var skippedSearches: [String]
    }

    static func importAlfred(
        core: AppCore, package: URL, options: AlfredImportOptions = .all
    ) async throws -> AlfredOutcome {
        // Off-main in an autoreleasepool, so the package's many plists drain at once.
        let result = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try AlfredPreferencesReader.read(package: package).selecting(options)
            }
        }.value
        guard
            await confirmExecutableImport(
                core: core, commands: result.commands.count,
                shortcuts: result.commands.filter { $0.hotkey != nil }.count,
                source: "This Alfred import")
        else { throw CancellationError() }

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
        var quicklinksImported = 0
        var quicklinksKeywordsUpdated = 0
        var quicklinksError: String?
        if !result.quicklinks.isEmpty {
            if core.quicklinks.isAvailable {
                let outcome = core.quicklinkCoordinator.addImportedQuicklinks(result.quicklinks)
                quicklinksImported = outcome.added.count
                quicklinksKeywordsUpdated = outcome.keywordsUpdated
                // Same reason as a Raycast import: a link grants no permission class.
                if quicklinksImported > 0 { core.settings.quicklinksEnabled = true }
            } else {
                quicklinksError = QuicklinkError.storageUnavailable.errorDescription
            }
        }
        // Merged, never replaced: the library is the user's own, Alfred's is only part of it.
        let added = core.customCommands.add(contentsOf: result.commands.map(\.command))

        var backup = SettingsBackup()
        if let scopes = result.searchScopes {
            var settings = SettingsBackup.SettingsData()
            settings.searchScopes = scopes
            backup.settings = settings
        }
        backup.hotkeys = alfredHotkeys(result, addedCommands: added)
        let summary = backup.apply(to: core)
        return AlfredOutcome(
            settingsFields: summary.settingsFields,
            shortcuts: summary.hotkeys,
            snippetsImported: snippetsImported,
            snippetsNeedEnabling: snippetsImported > 0 && !core.settings.snippetsEnabled,
            snippetsError: snippetsError,
            quicklinksImported: quicklinksImported,
            quicklinksKeywordsUpdated: quicklinksKeywordsUpdated,
            quicklinksError: quicklinksError,
            commandsImported: added.count,
            skippedWorkflows: result.skippedWorkflows,
            skippedSearches: result.skippedSearches)
    }

    /// A workflow's chord only exists once its command does, so it is read back off the store.
    private static func alfredHotkeys(
        _ result: AlfredImport.Result, addedCommands: [CustomCommand]
    ) -> SettingsBackup.HotkeyBackup? {
        var hotkeys = SettingsBackup.HotkeyBackup()
        var mapped = false
        if let palette = result.paletteHotkey {
            hotkeys.togglePalette = palette
            mapped = true
        }
        if let clipboard = result.clipboardHotkey {
            hotkeys.commands = [CommandID.clipboardHistory.rawValue: clipboard]
            mapped = true
        }
        var commands: [String: HotKeyBinding] = [:]
        for entry in result.commands {
            guard let binding = entry.hotkey,
                addedCommands.contains(where: { $0.id == entry.command.id })
            else { continue }
            commands[entry.command.id.uuidString.lowercased()] = binding
        }
        if !commands.isEmpty {
            hotkeys.customCommands = commands
            mapped = true
        }
        return mapped ? hotkeys : nil
    }

    /// Shared folder picker used by the Backup pane.
    static func pickAlfredPackage() -> URL? {
        let panel = NSOpenPanel()
        // Alfred.alfredpreferences is a file package: offered as a file it would be greyed out.
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Where Alfred keeps its preferences unless syncing moved them; nil when Alfred never ran here.
    static func defaultAlfredPackage() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Alfred/Alfred.alfredpreferences")
        return isAlfredPackage(url) ? url : nil
    }

    static func isAlfredPackage(_ url: URL) -> Bool {
        AlfredPreferencesReader.isPackage(url)
    }

    /// The preferences app holds Alfred's own hotkey window, so it goes with the app.
    private static let alfredBundleIDs = [
        "com.runningwithcrayons.Alfred", "com.runningwithcrayons.Alfred-Preferences"
    ]

    static func isAlfredBundleID(_ id: String) -> Bool { alfredBundleIDs.contains(id) }

    static func quitAlfred() {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier.map(isAlfredBundleID) == true
            && app.activationPolicy != .prohibited
        {
            app.terminate()
        }
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
        if summary.snippetsNeedEnabling { parts.append(snippetsNeedEnablingText) }
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

    /// No import may grant keystroke listening, so say the switch an imported keyword needs is off.
    private static let snippetsNeedEnablingText =
        "Turn on Snippets in Settings to use their keywords."

    /// Not everything an import applies settles in the running app, so say to relaunch.
    private static let restartAfterImportText = "Quit and reopen Tinycast to finish."

    /// One sentence per Raycast category that actually moved, shared by the pane and onboarding.
    static func raycastText(_ outcome: RaycastOutcome) -> String {
        var parts: [String] = []
        if let applied = appliedText(outcome.summary) { parts.append(applied) }
        if outcome.clipboardImported > 0 {
            parts.append("Imported \(outcome.clipboardImported) clipboard entries.")
        }
        if outcome.snippetsImported > 0 {
            let noun = outcome.snippetsImported == 1 ? "snippet" : "snippets"
            parts.append("Imported \(outcome.snippetsImported) \(noun).")
        }
        if outcome.snippetsNeedEnabling { parts.append(snippetsNeedEnablingText) }
        if let snippetsError = outcome.snippetsError {
            parts.append("Couldn’t import snippets: \(snippetsError)")
        }
        if outcome.quicklinksImported > 0 {
            let noun = outcome.quicklinksImported == 1 ? "quicklink" : "quicklinks"
            parts.append("Imported \(outcome.quicklinksImported) \(noun).")
        }
        if let quicklinksError = outcome.quicklinksError {
            parts.append("Couldn’t import quicklinks: \(quicklinksError)")
        }
        var message = parts.isEmpty ? nothingImportedText : parts.joined(separator: " ")
        if outcome.missingImages > 0 {
            message += " \(outcome.missingImages) images were unavailable and skipped."
        }
        if !parts.isEmpty { message += " \(restartAfterImportText)" }
        return message
    }

    /// One sentence per Alfred category that actually moved, so nothing is imported silently.
    static func alfredText(_ outcome: AlfredOutcome) -> String {
        var parts: [String] = []
        var applied: [String] = []
        if outcome.settingsFields > 0 { applied.append("\(outcome.settingsFields) settings") }
        if outcome.shortcuts > 0 { applied.append("\(outcome.shortcuts) shortcuts") }
        if !applied.isEmpty { parts.append("Applied " + applied.joined(separator: ", ") + ".") }
        if outcome.snippetsImported > 0 {
            parts.append("Imported \(outcome.snippetsImported) snippets.")
        }
        if outcome.snippetsNeedEnabling { parts.append(snippetsNeedEnablingText) }
        if let snippetsError = outcome.snippetsError {
            parts.append("Couldn’t import snippets: \(snippetsError)")
        }
        if outcome.quicklinksImported > 0 {
            let noun = outcome.quicklinksImported == 1 ? "quicklink" : "quicklinks"
            parts.append("Imported \(outcome.quicklinksImported) \(noun).")
        }
        if outcome.quicklinksKeywordsUpdated > 0 {
            parts.append("Updated the keyword on \(outcome.quicklinksKeywordsUpdated) existing.")
        }
        if let quicklinksError = outcome.quicklinksError {
            parts.append("Couldn’t import quicklinks: \(quicklinksError)")
        }
        if outcome.commandsImported > 0 {
            let noun = outcome.commandsImported == 1 ? "custom command" : "custom commands"
            parts.append("Imported \(outcome.commandsImported) \(noun) from Alfred workflows.")
        }
        if outcome.skippedWorkflows > 0 {
            let noun = outcome.skippedWorkflows == 1 ? "workflow was" : "workflows were"
            parts.append(
                "\(outcome.skippedWorkflows) \(noun) left out: only one running a single bash "
                    + "script from one trigger comes across.")
        }
        if !outcome.skippedSearches.isEmpty {
            parts.append("No search template for " + outcome.skippedSearches.joined(separator: ", ") + ".")
        }
        return parts.isEmpty ? nothingImportedText : parts.joined(separator: " ")
    }

    /// nil when no settings applied, so a caller can compose one combined sentence.
    static func appliedText(_ s: SettingsBackup.ApplySummary) -> String? {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        if s.aliases > 0 { parts.append("\(s.aliases) aliases") }
        if s.pinnedEmoji > 0 { parts.append("\(s.pinnedEmoji) pinned emoji and symbols") }
        if s.customCommands > 0 { parts.append("\(s.customCommands) custom commands") }
        if s.quicklinks > 0 { parts.append("\(s.quicklinks) quicklinks") }
        if s.windowLayouts > 0 { parts.append("\(s.windowLayouts) window layouts") }
        if s.windowRooms > 0 { parts.append("\(s.windowRooms) rooms") }
        if s.customWindowSizes > 0 {
            parts.append("\(s.customWindowSizes) custom window sizes")
        }
        guard !parts.isEmpty else { return nil }
        return "Applied " + parts.joined(separator: ", ") + "."
    }

    // MARK: - Settings file

    /// Where settings.json lives for this channel, as the pane and its dialog spell it.
    static var settingsFilePath: String {
        (AppPaths.settingsFile().path as NSString).abbreviatingWithTildeInPath
    }

    /// Turning the mirror on over a file that already exists asks which side wins.
    static func setSettingsFileEnabled(_ enabled: Bool, core: AppCore) async {
        guard enabled else { return core.stopSettingsFile() }
        guard FileManager.default.fileExists(atPath: AppPaths.settingsFile().path) else {
            return core.startSettingsFile(importing: false)
        }
        let choice = await core.choose(
            title: "Import the existing settings file?",
            message:
                "\(settingsFilePath) already exists. Import applies its settings here; Replace "
                + "overwrites it with the current ones.",
            symbol: importSymbol,
            options: [
                DialogAction(title: "Import"),
                DialogAction(title: "Replace", role: .destructive),
                DialogAction(title: "Cancel", role: .cancel)
            ],
            defaultIndex: 0)
        switch choice {
        case 0: core.startSettingsFile(importing: true)
        case 1: core.startSettingsFile(importing: false)
        default: break
        }
    }

    static func revealSettingsFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.settingsFile()])
    }

    private static func confirmExecutableImport(
        core: AppCore, commands: Int, shortcuts: Int, source: String = "This backup"
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
                "\(source) contains \(commandText) and \(shortcutText). Custom commands can run "
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
