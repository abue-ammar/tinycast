import Foundation

/// Whether a copy swapped in under the running app calls for a relaunch. docs/features/updates.md
enum BundleReplacementPolicy {
    /// What a bundle says it is, read off disk for the installed copy and from launch for ours.
    struct Identity: Equatable, Sendable {
        let bundleID: String
        let version: String
        let build: String

        init(bundleID: String, version: String, build: String) {
            self.bundleID = bundleID
            self.version = version
            self.build = build
        }

        init?(info: [String: Any]?) {
            guard let bundleID = info?["CFBundleIdentifier"] as? String,
                let version = info?["CFBundleShortVersionString"] as? String,
                let build = info?["CFBundleVersion"] as? String
            else { return nil }
            self.init(bundleID: bundleID, version: version, build: build)
        }
    }

    enum Decision: Equatable, Sendable {
        case keepRunning
        case wait
        case relaunch
    }

    /// A missing copy is mid-swap or uninstalled; the folder's next change re-asks either way.
    static func decide(
        running: Identity, installed: Identity?, isInstallingItself: Bool,
        isHostingHomebrew: Bool, blocker: UpdateReadiness.Blocker?
    ) -> Decision {
        guard !isInstallingItself, let installed, installed.bundleID == running.bundleID,
            installed != running
        else { return .keepRunning }
        // Quitting now would close the pipes of the `brew` still finishing this upgrade.
        if isHostingHomebrew { return .wait }
        if blocker != nil { return .wait }
        return .relaunch
    }

    /// Portable Ruby lives under the repository, which is `/opt/homebrew` or `/usr/local/Homebrew`.
    static func isHomebrew(executablePath: String) -> Bool {
        executablePath.contains("/Library/Homebrew/")
    }
}
