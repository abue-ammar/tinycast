import Foundation

/// Where to look and which match styles are legal there, as a table rather than per-root code.
struct UninstallSearchRoot: Hashable, Sendable {
    enum Base: Hashable, Sendable {
        case userLibrary
        case systemLibrary
    }

    enum MatchStyle: String, Hashable, Sendable, CaseIterable {
        case bundleID
        case groupContainer
        case displayName
    }

    let base: Base
    /// Relative to `base`, never empty.
    let relativePath: String
    let styles: Set<MatchStyle>

    func path(home: String) -> String {
        switch base {
        case .userLibrary: return home + "/Library/" + relativePath
        case .systemLibrary: return "/Library/" + relativePath
        }
    }

    /// Immediate children only; the home directory is absent. See docs/features/uninstall.md.
    static let all: [UninstallSearchRoot] = [
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Caches", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Containers", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Group Containers", styles: [.groupContainer]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Scripts",
            styles: [.bundleID, .groupContainer]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Preferences/ByHost", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Saved Application State", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "HTTPStorages", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "WebKit", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Cookies", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Autosave Information", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "LaunchAgents", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary,
            relativePath: "Application Support/com.apple.sharedfilelist/"
                + "com.apple.LSSharedFileList.ApplicationRecentDocuments",
            styles: [.bundleID]),
        // Plug-in wells: a child is a wrapper named after its product, suffix stripped.
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Internet Plug-Ins", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Services", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Spotlight", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Automator", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Input Methods", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/HAL", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Caches", styles: [.bundleID]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Logs", styles: [.bundleID]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "LaunchAgents", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "LaunchDaemons", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PrivilegedHelperTools", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Internet Plug-Ins",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/HAL",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName])
    ]

    /// Where a CLI launcher lands, scanned by link target and never by name.
    static let binDirectories: [String] = [
        "/usr/local/bin", "/opt/homebrew/bin", "~/.local/bin", "~/bin"
    ]
}
