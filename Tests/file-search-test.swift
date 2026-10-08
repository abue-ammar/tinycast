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

    static func main() {
        queryGrammar()
        recents()
        typeFilter()
        scopePolicy()
        pathPolicy()
        ignoreRules()
        policyResolution()
        resultModel()
        ranking()
        indexStructure()
        previewKind()

        print(failures == 0 ? "File search tests passed" : "\(failures) file search tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    static func query(_ raw: String) -> FileNameQuery {
        FileNameQuery(raw, homeDirectory: home, now: now)
    }

    static func queryGrammar() {
        expect(
            FileNameQuery.words(in: "  annual\treport  ") == ["annual", "report"],
            "words split on whitespace")
        expect(
            FileNameQuery.words(in: #"say "annual report" now"#) == ["say", "annual report", "now"],
            "double quotes keep a run of words together")
        expect(query(" \n ").isEmpty, "blank input is an empty query")

        let modes = query("plain 'exact ^start end$ !gone").tokens.map(\.mode)
        expect(modes == [.fuzzy, .exact, .prefix, .suffix, .exact], "prefixes pick a mode")
        expect(
            query("report !draft").negative.map(\.text) == [Array("draft".utf8)],
            "a bang negates a word")
        expect(
            query("src/main").positive.map(\.text) == [Array("src".utf8), Array("main".utf8)],
            "a slash splits a word into tokens a folder can answer")
        expect(
            query("Résumé").positive.first?.text == Array("resume".utf8),
            "tokens are folded the way the launcher folds")
        expect(
            query("a b c d e f g h i j").positive.count == FileNameQuery.positiveTokenLimit,
            "words past the token limit are dropped, not wrapped")

        let filtered = query("ext:.PDF,md kind:dir in:Documents report")
        expect(
            filtered.extensions == [Array("pdf".utf8), Array("md".utf8)],
            "ext takes a list, dropping dots and case")
        expect(filtered.kind == .folder, "kind takes its short spellings")
        expect(filtered.scope == "/Users/test/Documents", "a relative in: is anchored to home")
        expect(filtered.positive.map(\.text) == [Array("report".utf8)], "filters are not tokens")
        expect(
            query("foo:bar").positive.map(\.text) == [Array("foo:bar".utf8)],
            "an unknown key is searched for as typed")
        expect(query("ext: kind:other").isEmpty, "an empty or unknown value filters nothing")

        let seconds = UInt32(now.timeIntervalSince1970)
        expect(
            query("mtime:<7d").modified == (seconds - 604_800)...seconds,
            "<7d means within the last seven days")
        expect(query("modified:>1y").modified?.lowerBound == 0, ">1y reaches back to the epoch")
        expect(
            query("mtime:1d..2d").modified == (seconds - 172_800)...(seconds - 86_400),
            "a range is between two ages")
        expect(query("mtime:2d..1d").modified == nil, "a reversed range filters nothing")
        expect(FileNameQuery.resultLimit == 200, "the displayed result cap is fixed")
    }

    static func recents() {
        expect(
            FileSearchRecents.expression(stamp: .changed, excluding: ["*.tmp"], filter: .images)
                == "kMDItemFSContentChangeDate > $time.now(-259200)"
                + " && kMDItemContentTypeTree == \"public.image\""
                + " && kMDItemFSName != \"*.tmp\"cd",
            "a recents query is one stamp, narrowed by the filter and the ignore list")
        expect(
            FileSearchRecents.expression(stamp: .used)
                == "kMDItemLastUsedDate > $time.now(-2592000)",
            "an unfiltered recents query is the one date clause alone")
        expect(
            FileSearchRecents.Stamp.allCases.map(\.rawValue)
                == ["kMDItemFSContentChangeDate", "kMDItemLastUsedDate"],
            "both stamps are asked about: macOS records a last-used date for very few opens")
        expect(
            FileSearchRecents.Stamp.changed.window != FileSearchRecents.Stamp.used.window,
            "editing is constant, so the changed window is not the used one")
        expect(FileSearchRecents.limit == 20, "the blank screen's row count is fixed")
        expect(FileSearchRecents.candidateLimit == 1_000, "the Spotlight candidate cap is fixed")
    }

    static func typeFilter() {
        expect(
            FileSearchFilter.documents.accepts(pathExtension: "pages", isPackage: true),
            "a document package files under Documents by its extension")
        expect(
            FileSearchFilter.images.accepts(pathExtension: "PNG", isPackage: false)
                && !FileSearchFilter.images.accepts(pathExtension: "", isPackage: false),
            "an index entry is typed by its extension alone")
        expect(
            !FileSearchFilter.folders.accepts(pathExtension: "", isPackage: false),
            "Folders never admits a file entry; the index answers folders itself")
        expect(
            FileSearchFilter.documents.spotlightClause?.hasPrefix("(") == true,
            "a filter naming several types parenthesizes them, so the OR cannot leak")
        expect(FileSearchFilter.all.spotlightClause == nil, "All Types constrains nothing")

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
        expect(
            !FileSearchFilter.images.accepts(contentType: nil, isDirectory: false),
            "an unresolved type is a folder or nothing, never a guessed image")
    }

    static func scopePolicy() {
        func candidate(
            _ name: String, directory: Bool, hidden: Bool = false, package: Bool = false
        ) -> FileSearchScope.Candidate {
            FileSearchScope.Candidate(
                url: home.appending(path: name), isDirectory: directory, isHidden: hidden,
                isPackage: package)
        }
        let directories = FileSearchScope.select([
            candidate("Documents", directory: true),
            candidate("Developer", directory: true),
            candidate("Library", directory: true),
            candidate(".cache", directory: true, hidden: true),
            candidate("Project.xcodeproj", directory: true, package: true),
            candidate("Local.app", directory: true, package: true),
            candidate("Notes.txt", directory: false)
        ])
        expect(
            directories.map(\.lastPathComponent) == ["Documents", "Developer"],
            "only visible non-package directories become recents scopes")
    }

    static func pathPolicy() {
        let shipped = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults)
        for directory in FileSearchIgnoreList.defaults {
            expect(
                FileSearchRecents.isExcludedPath(
                    "/Users/test/Documents/App/\(directory)/file.txt", ignoring: shipped),
                "\(directory) descendants are excluded")
        }
        expect(
            FileSearchRecents.isExcludedPath(
                "/Users/test/Documents/App/.git/config", ignoring: shipped),
            "hidden ancestor paths are excluded")
        expect(
            FileSearchRecents.isExcludedPath(
                "/Users/test/Applications/Example.app/Contents/Info.plist", ignoring: shipped),
            "application-bundle contents are excluded")
        expect(
            !FileSearchRecents.isExcludedPath(
                "/Users/test/Documents/Building Plans/target-notes.txt", ignoring: shipped),
            "partial directory-name matches remain searchable")
        expect(
            !FileSearchRecents.isExcludedPath("/Users/test/Documents/Pods.txt", ignoring: shipped),
            "an excluded directory spelling is still valid as a filename")
        expect(
            !FileSearchRecents.isExcludedPath(
                "/Users/test/Documents/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "an empty list still leaves the structural rules in place")
        expect(
            FileSearchRecents.isExcludedPath(
                "/Users/test/.hidden/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "hidden paths are structural, not a pattern the user can drop")
    }

    static func ignoreRules() {
        let list = FileSearchIgnoreList(patterns: [
            "*.tmp", "**/[Cc]ache/**", "**/build-output/**", "Archive", "  ", "with\0nul"
        ])
        expect(list.excludes(path: "/Users/test/Documents/notes.TMP"), "a name glob folds case")
        expect(
            list.excludes(path: "/Users/test/Documents/scratch.tmp/keep.txt"),
            "a name glob matches at any depth, not only the last component")
        expect(
            list.excludes(path: "/Users/test/Developer/Cache/blob"),
            "a path glob matches a bracketed alternative")
        expect(
            list.excludes(path: "/Users/test/Developer/cache/blob"),
            "a path glob folds case too")
        expect(
            list.excludes(path: "/Users/test/Developer/app/build-output/index.js"),
            "a path glob matches an interior segment")
        expect(list.excludes(path: "/Users/test/archive/old.txt"), "a literal name folds case")
        expect(
            !list.excludes(path: "/Users/test/Documents/tmp-notes.txt"),
            "a name glob is anchored to the whole component, not a substring")
        expect(
            !list.excludes(path: "/Users/test/Documents/Archived/old.txt"),
            "a literal name never matches a longer component")
        expect(
            !FileSearchIgnoreList(patterns: []).excludes(path: "/Users/test/Documents/node_modules/a"),
            "the shipped rules are supplied by the policy, not baked into the matcher")
        expect(
            list.excludes(name: "ARCHIVE") && list.excludes(name: "x.tmp")
                && !list.excludes(name: "cache"),
            "a walk tests one name against the literal and name-glob buckets only")
        expect(
            list.hasPathPatterns && list.excludesWhole(path: "/Users/test/cache/blob")
                && !FileSearchIgnoreList(patterns: ["*.tmp"]).hasPathPatterns,
            "path globs are a separate, whole-path test a walk can skip when there are none")

        expect(
            list.spotlightNameExclusions == ["*.tmp"],
            "only bare `*` name globs are pushed into the Spotlight expression")
        expect(
            FileSearchIgnoreList(patterns: ["?.log", "a[bc].txt", "say\"hi\"", "back\\slash"])
                .spotlightNameExclusions.isEmpty,
            "Spotlight reads `?`, brackets and quotes literally, so those stay local")
    }

    static func policyResolution() {
        let policy = FileSearchPolicy(
            scopes: ["~", "~/Developer", "/Volumes/Work", "~/Developer"],
            ignorePatterns: ["*.log"], homeDirectory: home)
        expect(policy.includesHome, "a configured home root is held apart for expansion")
        expect(
            policy.directRoots.map(\.path) == ["/Users/test/Developer", "/Volumes/Work"],
            "every other root passes through verbatim, deduplicated in order")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/run.log"),
            "a user pattern applies outside home as well")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/node_modules/a.js"),
            "the shipped rules always apply on top of the user's")

        let away = FileSearchPolicy(
            scopes: ["~/Developer"], ignorePatterns: [], homeDirectory: home)
        expect(!away.includesHome, "dropping home drops the expansion with it")
        expect(
            FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: home).directRoots.isEmpty,
            "a cleared list resolves to no roots at all")
        expect(
            FileSearchScope.normalize(
                ["/Users/test/Developer", "~/Developer", "/etc"],
                homeDirectory: home) == ["~/Developer", "/etc"],
            "normalizing abbreviates home and drops the duplicate it creates")
        expect(
            FileSearchScope.expand("~", homeDirectory: home).path == "/Users/test",
            "a bare tilde expands to home itself")
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

    /// Paths under home; a trailing slash makes a folder. Every entry is a year old unless dated.
    static func makeIndex(_ paths: [String], modified: [String: UInt32] = [:]) -> FileNameIndex {
        var index = FileNameIndex()
        let stamp = UInt32(now.timeIntervalSince1970) - 31_536_000
        var folders = ["": index.addRoot(path: home.path)]
        var entries: [Int32: ContiguousArray<FileNameIndex.Entry>] = [:]
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            var parentPath = ""
            for (offset, component) in components.enumerated() {
                let childPath = parentPath.isEmpty ? component : parentPath + "/" + component
                let isFolder = offset < components.count - 1 || path.hasSuffix("/")
                let parent = folders[parentPath]!
                let name = index.intern(component)
                let date = modified[childPath] ?? stamp
                if isFolder, folders[childPath] == nil {
                    let folder = index.addDirectory(name: name, parent: parent)
                    folders[childPath] = folder
                    entries[parent, default: []].append(
                        FileNameIndex.Entry(name: name, modified: date, kind: .folder, directory: folder))
                } else if !isFolder {
                    let kind: FileNameIndex.Kind = component.hasSuffix(".pages") ? .package : .file
                    entries[parent, default: []].append(
                        FileNameIndex.Entry(name: name, modified: date, kind: kind))
                }
                parentPath = childPath
            }
        }
        for (folder, list) in entries { index.replaceEntries(of: folder, with: list) }
        return index
    }

    static func search(
        _ index: FileNameIndex, _ raw: String, filter: FileSearchFilter = .all, limit: Int = 200
    ) -> [String] {
        index.search(
            query(raw), filter: filter, now: UInt32(now.timeIntervalSince1970), limit: limit,
            homeDirectory: home
        ).map { String($0.id.dropFirst(home.path.count + 1)) }
    }

    static func ranking() {
        let index = makeIndex([
            "Archive/Report Annual.txt",
            "Archive/My Annual Report.txt",
            "Archive/Annual Report/",
            "Archive/Annual Notes.txt",
            "Documents/Résumé Final.pdf",
            "Documents/report draft.txt",
            "Documents/drafts/report.txt",
            "Projects/Tinycast/Palette.swift",
            "Projects/Tinycast/Notes.md",
            "Projects/Other/Palette.swift",
            "Pictures/report.png",
            "Pictures/Pitch.pages",
            "zeta/same.txt",
            "alpha/same.txt"
        ])
        let annual = search(index, "annual report")
        expect(annual.first == "Archive/Annual Report", "an exact name ranks first: \(annual)")
        expect(annual.contains("Archive/Report Annual.txt"), "word order does not gate a match")
        expect(!annual.contains("Archive/Annual Notes.txt"), "every positive word is required")

        expect(
            search(index, "resume final") == ["Documents/Résumé Final.pdf"],
            "matching is case- and diacritic-insensitive")
        expect(
            search(index, "repirt").contains("Pictures/report.png"),
            "a word of five letters or more forgives one typo")
        expect(search(index, "rpt").isEmpty == false, "a word is matched fuzzily, in order")
        expect(search(index, "'rpt").isEmpty, "a quote asks for the exact substring")

        let scoped = search(index, "tinycast palette")
        expect(
            scoped == ["Projects/Tinycast/Palette.swift"],
            "a word a folder answers narrows to that folder's descendants: \(scoped)")
        expect(
            !search(index, "projects tinycast").contains("Projects/Tinycast/Notes.md"),
            "at least one word has to match the name itself")
        let negated = search(index, "report !draft")
        expect(
            !negated.contains("Documents/report draft.txt")
                && !negated.contains("Documents/drafts/report.txt"),
            "a negated word vetoes the name and every folder above it: \(negated)")

        expect(search(index, "report ext:png") == ["Pictures/report.png"], "ext narrows by suffix")
        expect(
            search(index, "annual kind:folder") == ["Archive/Annual Report"],
            "kind:folder keeps folders only")
        expect(
            search(index, "palette in:Projects/Other") == ["Projects/Other/Palette.swift"],
            "in: confines a search to one folder")
        expect(search(index, "report", filter: .images) == ["Pictures/report.png"], "type filter")
        expect(
            search(index, "pitch", filter: .documents) == ["Pictures/Pitch.pages"],
            "a document package passes the Documents filter")
        expect(
            search(index, "tinycast", filter: .folders) == ["Projects/Tinycast"],
            "the Folders filter keeps undescended and descended folders alike")
        expect(
            search(index, "same") == ["alpha/same.txt", "zeta/same.txt"],
            "equal scores fall back to the name, then the path")

        let dated = makeIndex(
            ["old/report.txt", "new/report.txt"],
            modified: ["new/report.txt": UInt32(now.timeIntervalSince1970) - 3_600])
        expect(search(dated, "report").first == "new/report.txt", "a recent change ranks higher")
        expect(search(dated, "report mtime:<1d") == ["new/report.txt"], "mtime filters by age")

        let capped = makeIndex((0..<205).map { "Archive/Report \($0).txt" })
        expect(search(capped, "report", limit: 200).count == 200, "the result cap holds")
        expect(search(index, "").isEmpty, "an empty query lists nothing; recents are Spotlight's")
    }

    static func indexStructure() {
        var index = makeIndex(["a/b/c.txt", "a/b/d.txt", "a/e.txt", "f.txt"])
        expect(index.entryCount == 6, "every file and folder is an entry: \(index.entryCount)")
        guard let b = index.directory(atPath: "/Users/test/a/b") else {
            return expect(false, "a descended folder is found by path")
        }
        expect(index.path(of: b) == "/Users/test/a/b", "a folder's path is rebuilt from parents")
        expect(index.directory(atPath: "/Users/test/a/missing") == nil, "an unknown path is nil")
        expect(index.directory(atPath: "/Elsewhere") == nil, "a path outside every root is nil")

        guard let a = index.directory(atPath: "/Users/test/a") else { return }
        let kept = ContiguousArray(index.entries(of: a).filter { $0.directory == nil })
        index.replaceEntries(of: a, with: kept)
        expect(index.entryCount == 3, "dropping a folder drops its whole subtree")
        expect(index.directory(atPath: "/Users/test/a/b") == nil, "and its path stops resolving")
        expect(search(index, "c.txt").isEmpty, "and its files stop matching")
        expect(index.directoryCount == 2, "the subtree's folder slots are freed")
        expect(
            index.addDirectory(name: index.intern("g"), parent: a) == b,
            "and a freed slot is the next one handed out")
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
