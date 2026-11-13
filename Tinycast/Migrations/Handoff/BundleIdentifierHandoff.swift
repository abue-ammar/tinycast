import AppKit
import ServiceManagement

/// What a copy from before the bundle id move installs: it puts the app it carries in its place.
@main
enum BundleIdentifierHandoff {
    /// `BundleIdentifierMigration.launchAtLoginKey`; only the old id can still read the login item.
    private static let launchAtLoginKey = "BundleIdentifierHandoff.launchAtLogin"

    static func main() async {
        let handoff = Bundle.main.bundleURL
        let helpers = handoff.appending(components: "Contents", "Helpers")
        guard
            let successor = (try? FileManager.default.contentsOfDirectory(
                at: helpers, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "app" })
        else { exit(EXIT_FAILURE) }

        UserDefaults.standard.set(SMAppService.mainApp.status == .enabled, forKey: launchAtLoginKey)
        try? await SMAppService.mainApp.unregister()

        let installed = swap(handoff, for: successor)
        let configuration = NSWorkspace.OpenConfiguration()
        // This process still runs from that path, and opening it again would only re-activate us.
        configuration.createsNewApplicationInstance = true
        _ = try? await NSWorkspace.shared.openApplication(at: installed, configuration: configuration)
    }

    /// Whichever copy ends up runnable, so a failed swap still opens the app rather than nothing.
    private static func swap(_ handoff: URL, for successor: URL) -> URL {
        let files = FileManager.default
        guard
            let staging = try? files.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: handoff, create: true)
        else { return successor }
        let staged = staging.appending(path: successor.lastPathComponent)
        guard (try? files.moveItem(at: successor, to: staged)) != nil else { return successor }
        guard let installed = try? files.replaceItemAt(handoff, withItemAt: staged) else { return staged }
        try? files.removeItem(at: staging)
        return installed
    }
}
