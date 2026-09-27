import AppKit

/// The open panel a Settings row uses to pick a command, hidden folders shown: `~/.local/bin` is one.
@MainActor
enum ExecutablePicker {
    static func choose(message: String, startingAt directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.resolvesAliases = false
        panel.prompt = "Use Command"
        panel.message = message
        panel.directoryURL = directory
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
