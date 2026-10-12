import Foundation
import UniformTypeIdentifiers

@main
struct FileSearchTests {
    nonisolated(unsafe) static var failures = 0
    static let home = URL(fileURLWithPath: "/Users/test")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func result(_ path: String, folder: Bool = false) -> FileSearchResult {
        FileSearchResult(url: home.appending(path: path), isDirectory: folder, homeDirectory: home)
    }

    static func score(_ query: String, _ name: String, prior: Int8 = 2) -> Int? {
        guard let prepared = FileSearchQuery.prepare(query) else { return nil }
        var name = name
        return name.withUTF8 { bytes in
            FileSearchQuery.score(
                prepared, name: bytes, mask: FileSearchQuery.nameMask(bytes), prior: prior)
        }
    }

    static func main() {
        queryMatching()
        ranking()
        typeFilter()
        ignoreRules()
        policy()
        scopes()
        resultModel()
        previewKind()

        print(failures == 0 ? "File search tests passed" : "\(failures) file search tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func queryMatching() {
        expect(
            FileSearchQuery.terms(in: "  annual\treport  ") == ["annual", "report"],
            "terms split on whitespace")
        expect(FileSearchQuery.prepare(" \n ") == nil, "empty input prepares no query")
        expect(
            FileSearchQuery.prepare("Annual  Report")?.whole == Array("annual report".utf8),
            "the whole query is folded with single spaces")
        expect(score("annual report", "My Annual Report.pdf") != nil, "every term in any position")
        expect(score("annual report", "Annual Notes.pdf") == nil, "every term is required")
        expect(score("readme", "README.md") != nil, "matching ignores case")
        expect(score("resume final", "Résumé Final.pdf") != nil, "matching ignores diacritics")
        expect(score("RÉSUMÉ", "resume.txt") != nil, "a folded query matches a plain name")
        expect(score("report", "rep-ort.txt") == nil, "a term is a substring, not a subsequence")

        var accented = "Résumé"
        let mask = accented.withUTF8(FileSearchQuery.nameMask)
        let query = FileSearchQuery.prepare("resume")!
        expect(mask & query.mask == query.mask, "a name's mask covers its folded spelling")
        expect(
            mask & FileSearchQuery.nonASCIIBit != 0, "a non-ASCII name is flagged for the slow path")

        var haystack = "xxABCabc"
        expect(
            haystack.withUTF8 { FileSearchQuery.find(Array("abc".utf8), in: $0) } == 2,
            "find returns the first case-insensitive occurrence")
    }

    static func ranking() {
        let exact = score("report", "report")!
        let prefix = score("report", "report.pdf")!
        let boundary = score("report", "Annual report.pdf")!
        let inner = score("report", "misreported.txt")!
        expect(exact > prefix && prefix > boundary && boundary > inner, "exact, prefix, word, inner")
        expect(
            score("report", "report.pdf")! > score("report", "reporting.pdf")!,
            "a whole word beats a longer one that starts the same")
        expect(
            score("index", "fileIndex.swift")! > score("index", "reindexer.swift")!,
            "a camel-case step is a word boundary")
        expect(
            score("annual report", "Annual Report 2024.pdf")!
                > score("annual report", "Report Annual.pdf")!,
            "terms typed in order rank above the same terms reversed")
        expect(
            score("notes", "notes.txt", prior: 2)! - score("notes", "notes.txt", prior: 0)! == 3_000,
            "where a file lives weighs as much as how well its name matches")
        expect(
            score("notes", "notes.txt", prior: 0)! > score("notes", "my notes.txt", prior: 0)!,
            "within one location, the better match wins")
    }

    static func typeFilter() {
        expect(
            FileSearchFilter.all.accepts(contentType: nil, isDirectory: false),
            "All Types admits a file whose type never resolved")
        expect(
            FileSearchFilter.folders.accepts(contentType: .folder, isDirectory: true)
                && FileSearchFilter.folders.accepts(contentType: nil, isDirectory: true),
            "Folders admits a directory whether or not its type resolved")
        expect(
            !FileSearchFilter.folders.accepts(contentType: .png, isDirectory: false),
            "Folders rejects a file")
        expect(
            FileSearchFilter.images.accepts(contentType: .png, isDirectory: false)
                && !FileSearchFilter.images.accepts(contentType: .mp3, isDirectory: false),
            "a type filter admits what conforms to it and nothing else")
        expect(
            FileSearchFilter.documents.accepts(contentType: .swiftSource, isDirectory: false),
            "source files conform to public.text, so Documents keeps them")

        let png = FileSearchFilter.contentType(extension: "png", isDirectory: false)
        expect(png?.conforms(to: .image) == true, "a file's type comes from its extension")
        expect(
            FileSearchFilter.contentType(extension: "", isDirectory: true) == .folder,
            "a plain folder is a folder")
        expect(
            FileSearchFilter.contentType(extension: "v2", isDirectory: true) == .folder,
            "a dotted folder name is still a folder")
        let rtfd = FileSearchFilter.contentType(extension: "rtfd", isDirectory: true)
        expect(
            FileSearchFilter.documents.accepts(contentType: rtfd, isDirectory: true)
                && !FileSearchFilter.folders.accepts(contentType: rtfd, isDirectory: true),
            "a document package files under Documents, not Folders")
    }

    static func ignoreRules() {
        let list = FileSearchIgnoreList(
            patterns: [
                "*.tmp", "**/[Cc]ache/**", "Archive", "~/Movies", "  ", "with\0nul"
            ], homeDirectory: home)
        expect(list.excludes(name: "notes.TMP", path: "/Users/test/notes.TMP"), "a name glob folds case")
        expect(list.excludes(name: "archive", path: "/x/archive"), "a literal name folds case")
        expect(!list.excludes(name: "Archived", path: "/x/Archived"), "a literal is the whole name")
        expect(!list.excludes(name: "tmp-notes.txt", path: "/x/tmp-notes.txt"), "a glob is anchored")
        expect(
            list.excludes(name: "blob", path: "/Users/test/Developer/Cache/blob"),
            "a path glob matches a bracketed alternative")
        expect(
            list.excludes(name: "Movies", path: "/Users/test/Movies"),
            "a tilde path names that one folder")
        expect(
            !list.excludes(name: "Movies", path: "/Users/test/Documents/Movies"),
            "a tilde path is not a name pattern")

        let shipped = FileSearchIgnoreList(
            patterns: FileSearchIgnoreList.defaults, homeDirectory: home)
        for name in FileSearchIgnoreList.defaults {
            expect(shipped.excludes(name: name, path: "/x/\(name)"), "\(name) is skipped")
        }
        expect(
            !shipped.excludes(name: ".git", path: "/x/.git"),
            "hidden folders are indexed unless a pattern says otherwise")
    }

    static func policy() {
        let policy = FileSearchPolicy(
            scopes: ["~/Developer", "~", "/Volumes/Work", "~/Developer"],
            ignorePatterns: ["*.log"], homeDirectory: home)
        expect(
            policy.roots == ["/Users/test", "/Volumes/Work"],
            "roots are deduplicated, and a scope inside another folds into it")
        expect(
            FileSearchPolicy(scopes: ["/", "~"], ignorePatterns: [], homeDirectory: home).roots
                == ["/"],
            "the whole disk covers home")
        expect(
            FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: home).roots.isEmpty,
            "a cleared list resolves to no roots at all")
        expect(
            policy.ignore.excludes(name: "run.log", path: "/Volumes/Work/run.log")
                && policy.ignore.excludes(name: "node_modules", path: "/Volumes/Work/node_modules"),
            "the user's patterns and the shipped ones both apply")

        let same = FileSearchPolicy(
            scopes: ["~/Developer", "~", "/Volumes/Work", "~/Developer"],
            ignorePatterns: ["*.log"], homeDirectory: home)
        expect(policy == same && policy.fingerprint == same.fingerprint, "the fingerprint is stable")
        let other = FileSearchPolicy(
            scopes: ["~"], ignorePatterns: ["*.txt"], homeDirectory: home)
        expect(policy.fingerprint != other.fingerprint, "changing the settings changes the fingerprint")

        let priors: [(String, Int8)] = [
            ("/Users/test", 2),
            ("/Users/test/Documents/Work", 2),
            ("/Users/test/.config", 0),
            ("/Users/test/Library/Caches", 0),
            ("/Users/test/Library/CloudStorage/Dropbox/Team", 2),
            ("/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Notes", 2),
            ("/Users/test/Developer/Tool.app/Contents", 0),
            ("/Applications", 1),
            ("/Applications/Xcode.app", 0),
            ("/Users/Shared", 1),
            ("/System/Library", 0),
            ("/private/var", 0)
        ]
        for (path, expected) in priors {
            expect(policy.prior(of: path) == expected, "\(path) ranks \(expected)")
        }
    }

    static func scopes() {
        expect(
            FileSearchScope.normalize(
                ["/Users/test/Developer", "~/Developer", "/etc"], homeDirectory: home)
                == ["~/Developer", "/etc"],
            "normalizing abbreviates home and drops the duplicate it creates")
        expect(
            FileSearchScope.normalize(["~/a", "/", "~"], homeDirectory: home) == ["/"],
            "adding the whole disk absorbs every other scope")
        expect(
            FileSearchScope.expand("~", homeDirectory: home).path == "/Users/test",
            "a bare tilde expands to home itself")
        expect(FileSearchScope.contains("/", "/Users"), "the disk root contains everything")
        expect(!FileSearchScope.contains("/Users/a", "/Users/ab"), "containment is per component")
    }

    static func resultModel() {
        let nested = result("Documents/Annual Report.pdf")
        expect(nested.id == "/Users/test/Documents/Annual Report.pdf", "identity is the full path")
        expect(nested.name == "Annual Report.pdf", "the full filename keeps its extension")
        expect(nested.parentPath == "~/Documents", "the parent path abbreviates home")
        expect(result("Notes.txt").parentPath == "~", "a home-root item has a bare tilde parent")
        expect(
            nested.parentName == "Documents" && result("Notes.txt").parentName == "test",
            "the parent's own name is what a folder row prefixes itself with")
    }

    static func previewKind() {
        expect(FileSearchPreviewKind(pathExtension: "swift") == .quickLook, "declared text")
        expect(FileSearchPreviewKind(pathExtension: "pdf") == .pdf, "a PDF draws in process")
        expect(FileSearchPreviewKind(pathExtension: "mov") == .media, "a movie plays")
        expect(FileSearchPreviewKind(pathExtension: "jsx") == nil, "undeclared waits on bytes")
        expect(FileSearchPreviewKind(pathExtension: "ts") == nil, ".ts: TypeScript or MPEG-TS")

        let source = Data("export const x = () => <div>é</div>\n".utf8)
        expect(
            FileSearchPreviewKind(pathExtension: "ts", head: source, isWholeFile: true) == .text,
            "TypeScript source is text")
        expect(
            FileSearchPreviewKind(
                pathExtension: "ts", head: Data([0x47, 0x40, 0x00, 0x10]), isWholeFile: false)
                == .media,
            "an MPEG-TS stream still plays")
        expect(
            FileSearchPreviewKind(pathExtension: "jsx", head: Data([0xFF, 0x00]), isWholeFile: true)
                == .quickLook,
            "undeclared binary falls back to QuickLook")

        let cut = Data("café".utf8).dropLast()
        expect(FileSearchPreviewKind.isText(cut, isWholeFile: false), "a read may cut a character")
        expect(!FileSearchPreviewKind.isText(cut, isWholeFile: true), "a whole file must be UTF-8")
        expect(
            !FileSearchPreviewKind.isText(Data("abc".utf8) + [0xFF], isWholeFile: false),
            "a read forgives a cut character, not a malformed byte")
    }
}
