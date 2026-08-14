import Foundation

/// Installs an extension's dependencies before a build. Only a source registry needs one.
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

    /// `automatic`'s order: fastest and most disk-frugal first, npm last as the one always there.
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

    /// Not the frozen-lockfile variants: a committed lockfile is often stale, and failing helps nobody.
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

    /// Where to look, for a GUI app inheriting none of a shell's PATH: Homebrew, Volta, asdf, fnm, nvm.
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

    /// `ray build` runs on Node, and bun is the one manager that doesn't imply it.
    static func nodeURL(in fileManager: FileManager = .default) -> URL? {
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("node")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
