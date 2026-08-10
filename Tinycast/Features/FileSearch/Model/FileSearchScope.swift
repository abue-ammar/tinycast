import Foundation

enum FileSearchScope {
    struct Candidate: Sendable {
        let url: URL
        let isDirectory: Bool
        let isHidden: Bool
        let isPackage: Bool
        let isApplication: Bool
    }

    struct Selection: Sendable {
        let directories: [URL]
        let rootItems: [Candidate]
    }

    static func select(_ candidates: [Candidate]) -> Selection {
        var directories: [URL] = []
        var rootItems: [Candidate] = []
        for candidate in candidates
        where !candidate.isHidden && !candidate.isApplication
            && candidate.url.lastPathComponent.caseInsensitiveCompare("Library") != .orderedSame
        {
            rootItems.append(candidate)
            if candidate.isDirectory && !candidate.isPackage {
                directories.append(candidate.url)
            }
        }
        return Selection(directories: directories, rootItems: rootItems)
    }
}
