import Foundation

/// The package manager used to install an extension's dependencies before building it.
///
/// Only a GitHub registry needs one — Raycast's store serves extensions already built. Which one to
/// use is a real preference: a machine that has pnpm often doesn't want npm's node_modules, and a bun
/// user wants bun. `automatic` picks the first one installed, in the order below.
enum ExtensionPackageManager: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case pnpm
    case npm
    case yarn
    case bun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .pnpm: return "pnpm"
        case .npm: return "npm"
        case .yarn: return "Yarn"
        case .bun: return "Bun"
        }
    }

    /// Tried in order by `automatic`: fastest and most disk-frugal first, npm last as the one that is
    /// always there.
    static let preferenceOrder: [ExtensionPackageManager] = [.pnpm, .bun, .yarn, .npm]

    var executableName: String {
        switch self {
        case .automatic: return ""
        case .pnpm: return "pnpm"
        case .npm: return "npm"
        case .yarn: return "yarn"
        case .bun: return "bun"
        }
    }

    /// Installs dependencies from the manifest. Deliberately not the frozen-lockfile variants: an
    /// extension's committed lockfile is often out of date with its manifest, and failing the install
    /// over that helps nobody.
    var installArguments: [String] {
        switch self {
        case .automatic: return []
        case .pnpm: return ["install", "--ignore-scripts"]
        case .npm: return ["install", "--ignore-scripts", "--no-audit", "--no-fund"]
        case .yarn: return ["install", "--ignore-scripts"]
        case .bun: return ["install", "--ignore-scripts"]
        }
    }

    /// Runs the manifest's `build` script, which for a Raycast extension is `ray build`.
    var buildArguments: [String] {
        switch self {
        case .automatic: return []
        case .pnpm: return ["run", "build"]
        case .npm: return ["run", "build"]
        case .yarn: return ["run", "build"]
        case .bun: return ["run", "build"]
        }
    }

    /// Where a package manager is likely to be, for a GUI app that inherits none of a shell's PATH.
    /// Homebrew (both architectures), Volta, asdf, fnm, nvm's default alias, and the system prefixes.
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        NSHomeDirectory() + "/.volta/bin",
        NSHomeDirectory() + "/.bun/bin",
        NSHomeDirectory() + "/.asdf/shims",
        NSHomeDirectory() + "/.local/share/fnm/aliases/default/bin",
        NSHomeDirectory() + "/.nvm/versions/node/current/bin",
        NSHomeDirectory() + "/.yarn/bin",
        NSHomeDirectory() + "/.npm-global/bin"
    ]

    /// The executable, or nil when it isn't installed. `automatic` resolves to the first one found.
    func resolve(in fileManager: FileManager = .default) -> (manager: ExtensionPackageManager, url: URL)? {
        guard self != .automatic else {
            for candidate in Self.preferenceOrder {
                if let found = candidate.resolve(in: fileManager) { return found }
            }
            return nil
        }
        for directory in Self.searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executableName)
            if fileManager.isExecutableFile(atPath: candidate.path) { return (self, candidate) }
        }
        return nil
    }

    /// Node itself, which `ray build` runs on. A package manager without it can't build anything, and
    /// bun is the one that doesn't imply it.
    static func nodeURL(in fileManager: FileManager = .default) -> URL? {
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("node")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
