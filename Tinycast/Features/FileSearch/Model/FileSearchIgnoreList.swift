import Darwin
import Foundation

/// gitignore-flavoured: a bare pattern matches a name anywhere, one with `/` the whole path.
struct FileSearchIgnoreList: Sendable, Equatable {
    /// Compiled in, not stored, so changing the shipped rules reaches existing installs.
    static let defaults = [
        "node_modules", ".git", ".build", "build", "dist", "target", "DerivedData", "Pods", ".next",
        ".venv", "*.photoslibrary", "~/.Trash", "~/.cache", "~/.npm", "~/Library/Application Support",
        "~/Library/Caches", "~/Library/Containers", "~/Library/Developer", "~/Library/Group Containers",
        "~/Library/Mail", "/Library/Caches", "/private/var/folders"
    ]

    /// A shipped rule is governed by `removedDefaults` alone, even when `added` repeats it.
    static func patterns(added: [String], removedDefaults: [String]) -> [String] {
        var seen = Set(defaults)
        return defaults.filter { !removedDefaults.contains($0) } + added.filter { seen.insert($0).inserted }
    }

    private let literalNames: [Glob]
    private let nameGlobs: [Glob]
    private let pathGlobs: [Glob]

    init(patterns: [String], homeDirectory: URL) {
        var literalNames: [Glob] = []
        var nameGlobs: [Glob] = []
        var pathGlobs: [Glob] = []
        let home = homeDirectory.path
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            // An interior NUL would silently truncate the pattern once it reaches `fnmatch`.
            guard !trimmed.isEmpty, !trimmed.contains("\0") else { continue }
            if trimmed.hasPrefix("~/") {
                pathGlobs.append(Glob(home + trimmed.dropFirst()))
            } else if trimmed.contains("/") {
                pathGlobs.append(Glob(trimmed))
            } else if trimmed.contains(where: Glob.isMetacharacter) {
                nameGlobs.append(Glob(trimmed))
            } else {
                literalNames.append(Glob(trimmed))
            }
        }
        self.literalNames = literalNames
        self.nameGlobs = nameGlobs
        self.pathGlobs = pathGlobs
    }

    func excludes(name: UnsafePointer<CChar>, length: Int, path: () -> String) -> Bool {
        for literal in literalNames where literal.length == length {
            if literal.equals(name) { return true }
        }
        for glob in nameGlobs where glob.matches(name) { return true }
        guard pathGlobs.contains(where: { $0.couldMatchName(name) }) else { return false }
        let path = path()
        return path.withCString { path in pathGlobs.contains { $0.matches(path) } }
    }

    func excludes(name: String, path: String) -> Bool {
        name.withCString { excludes(name: $0, length: name.utf8.count, path: { path }) }
    }
}

/// One compiled pattern; `fnmatch` runs without `FNM_PATHNAME`, so `*` spans `/`.
private struct Glob: Sendable, Equatable {
    private let terminated: ContiguousArray<CChar>
    private let literalPathName: ContiguousArray<CChar>?
    let length: Int

    init(_ pattern: String) {
        terminated = pattern.utf8CString
        length = terminated.count - 1
        if let slash = pattern.lastIndex(of: "/"), !pattern.hasSuffix("/"),
            !pattern.contains(where: { Self.isMetacharacter($0) || $0 == "\\" })
        {
            literalPathName = String(pattern[pattern.index(after: slash)...]).utf8CString
        } else {
            literalPathName = nil
        }
    }

    static func isMetacharacter(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }

    func equals(_ name: UnsafePointer<CChar>) -> Bool {
        terminated.withUnsafeBufferPointer { strcasecmp($0.baseAddress!, name) == 0 }
    }

    func couldMatchName(_ name: UnsafePointer<CChar>) -> Bool {
        guard let literalPathName else { return true }
        return literalPathName.withUnsafeBufferPointer { fnmatch($0.baseAddress!, name, FNM_CASEFOLD) == 0 }
    }

    func matches(_ candidate: UnsafePointer<CChar>) -> Bool {
        terminated.withUnsafeBufferPointer { fnmatch($0.baseAddress!, candidate, FNM_CASEFOLD) == 0 }
    }
}
