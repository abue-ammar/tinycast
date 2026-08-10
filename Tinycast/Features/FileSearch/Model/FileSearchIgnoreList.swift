import Darwin
import Foundation

/// gitignore-flavoured excludes: a bare pattern matches any path component, one with `/` the whole path.
struct FileSearchIgnoreList: Sendable, Equatable {
    /// Compiled in rather than stored, so changing the shipped rules reaches installs that already ran.
    static let defaults = ["node_modules", "DerivedData", "build", "dist", "target", "Pods"]

    private let literalNames: Set<String>
    private let nameGlobs: [Glob]
    private let pathGlobs: [Glob]

    init(patterns: [String]) {
        var literalNames: Set<String> = []
        var nameGlobs: [Glob] = []
        var pathGlobs: [Glob] = []
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            // An interior NUL would silently truncate the pattern once it reaches `fnmatch`.
            guard !trimmed.isEmpty, !trimmed.contains("\0") else { continue }
            if trimmed.contains("/") {
                pathGlobs.append(Glob(trimmed))
            } else if trimmed.contains(where: Glob.isMetacharacter) {
                nameGlobs.append(Glob(trimmed))
            } else {
                literalNames.insert(trimmed.lowercased())
            }
        }
        self.literalNames = literalNames
        self.nameGlobs = nameGlobs
        self.pathGlobs = pathGlobs
    }

    func excludes(path: String) -> Bool {
        for component in path.split(separator: "/") {
            let name = String(component)
            if literalNames.contains(name.lowercased()) { return true }
            if nameGlobs.contains(where: { $0.matches(name) }) { return true }
        }
        return pathGlobs.contains { $0.matches(path) }
    }

    /// Name globs Spotlight can evaluate itself, so ignored files never fill the candidate cap.
    var spotlightNameExclusions: [String] {
        nameGlobs.filter(\.isSpotlightExpressible).map(\.pattern)
    }
}

/// One compiled pattern. `fnmatch` runs without `FNM_PATHNAME`, so `*` spans `/` and `**/tmp/**` works.
private struct Glob: Sendable, Equatable {
    let pattern: String
    private let terminated: ContiguousArray<CChar>

    init(_ pattern: String) {
        self.pattern = pattern
        terminated = pattern.utf8CString
    }

    static func isMetacharacter(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }

    /// Spotlight treats `?` and `[` as literals and only understands `*`, so anything else stays local.
    var isSpotlightExpressible: Bool {
        !pattern.contains(where: { $0 == "?" || $0 == "[" || $0 == "\"" || $0 == "\\" })
    }

    func matches(_ candidate: String) -> Bool {
        terminated.withUnsafeBufferPointer { pattern in
            candidate.withCString { fnmatch(pattern.baseAddress!, $0, FNM_CASEFOLD) == 0 }
        }
    }
}
