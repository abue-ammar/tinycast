import AppKit

/// The open panel a Settings row uses to pick the one folder a feature keeps its files in.
@MainActor
enum FolderPicker {
    static func choose(message: String, startingAt directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use Folder")
        panel.message = message
        panel.directoryURL = directory
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
