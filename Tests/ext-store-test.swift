import Foundation

/// The parts of installing from a registry that can be checked without a network.
@main
@MainActor
struct ExtensionStoreTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        registryParsing()
        registryDefaults()
        storeResponse()
        gitHubTree()
        manifestSummary()
        packageManagers()
        abbreviation()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Registry

    static func registryParsing() {
        print("\n# registry parsing")

        let plain = ExtensionRegistry.parse("https://github.com/raycast/extensions")
        check("a repository URL parses", plain?.owner == "raycast" && plain?.repository == "extensions")
        check("and defaults to extensions/ on main", plain?.path == "extensions" && plain?.ref == "main")

        let short = ExtensionRegistry.parse("someone/my-extensions")
        check("owner/repo alone parses", short?.owner == "someone")

        let git = ExtensionRegistry.parse("git@example/nope")
        check("a non-GitHub remote still yields owner/repo", git != nil)

        let deep = ExtensionRegistry.parse(
            "https://github.com/raycast/extensions/tree/abc123/extensions")
        check("a tree link keeps its ref", deep?.ref == "abc123")
        check("and its path", deep?.path == "extensions")

        let nested = ExtensionRegistry.parse("github.com/me/repo/tree/dev/packages/raycast")
        check("a nested path survives", nested?.path == "packages/raycast")
        check("with its branch", nested?.ref == "dev")

        let dotGit = ExtensionRegistry.parse("https://github.com/me/repo.git")
        check("a .git suffix is dropped", dotGit?.repository == "repo")

        check("junk is rejected", ExtensionRegistry.parse("not a url") == nil)
        check("a bare owner is rejected", ExtensionRegistry.parse("raycast") == nil)

        let named = ExtensionRegistry.parse("me/repo", name: "Mine")
        check("an explicit name wins", named?.name == "Mine")
        check("and is derived when absent", ExtensionRegistry.parse("me/repo")?.name == "me/repo")

        let messy = ExtensionRegistry(kind: .github, name: "x", path: "/extensions/")
        check("a path is normalized", messy.path == "extensions")
    }

    static func registryDefaults() {
        print("\n# registry defaults")
        check("both defaults ship", ExtensionRegistry.defaults.count == 2)
        check("the store comes first", ExtensionRegistry.defaults.first?.kind == .raycastStore)
        check("both are built in", ExtensionRegistry.defaults.allSatisfy(\.isBuiltIn))
        // Only the store is searched out of the box: it is the one that needs no toolchain.
        check("the store is on by default", ExtensionRegistry.store.isEnabled)
        check("the source registry is not", !ExtensionRegistry.officialGitHub.isEnabled)
        check("an added registry starts on", ExtensionRegistry.parse("me/repo")?.isEnabled == true)
        check("an added one is not", ExtensionRegistry.parse("me/repo")?.isBuiltIn == false)
        // Persisted by id, so a stable id is what keeps a stored copy recognisable as built-in.
        check(
            "built-in ids are fixed",
            ExtensionRegistry.store.id.uuidString == "00000000-0000-0000-0000-000000000001")

        let encoded = try? JSONEncoder().encode(ExtensionRegistry.defaults)
        let decoded = encoded.flatMap { try? JSONDecoder().decode([ExtensionRegistry].self, from: $0) }
        check("registries round-trip", decoded == ExtensionRegistry.defaults)
    }

    // MARK: - Raycast's store

    static let storePayload = """
        {"data":[
          {"id":"abc","name":"coffee","title":"Coffee","description":"Prevent sleep",
           "author":{"name":"Max Schmidt","handle":"mooxl"},
           "icons":{"light":"https://files.raycast.com/icon","dark":null},
           "commands":[{"name":"caffeinate"},{"name":"decaffeinate"}],
           "download_count":124218,"status":"active",
           "download_url":"https://example.com/coffee.zip",
           "commit_sha":"c325a1a","relative_path":"extensions/coffee/"},
          {"id":"def","name":"gone","title":"Gone","status":"active"},
          {"id":"ghi","name":"dead","title":"Dead","status":"kill_listed",
           "download_url":"https://example.com/dead.zip"}
        ]}
        """

    static func storeResponse() {
        print("\n# store response")
        guard
            let listings = try? ExtensionStoreResponse.parseStore(
                Data(storePayload.utf8), registry: .store)
        else {
            check("the store payload parses", false)
            return
        }
        check("only installable entries survive", listings.count == 1)

        guard let coffee = listings.first else { return }
        check("the title is read", coffee.title == "Coffee")
        check("the author's name wins over the handle", coffee.author == "Max Schmidt")
        check("commands are counted", coffee.commandCount == 2)
        check("downloads are read", coffee.downloadCount == 124_218)
        let icon = "https://files.raycast.com/icon"
        check("the icon resolves", coffee.iconURL(isDark: false)?.absoluteString == icon)
        // The fixture's `dark` is null, so the other side has to stand in for it.
        check("a missing side falls back", coffee.iconURL(isDark: true)?.absoluteString == icon)
        check("it carries its registry", coffee.registryID == ExtensionRegistry.store.id)
        if case .prebuiltZip(let url) = coffee.source {
            check("the source is the zip", url.absoluteString == "https://example.com/coffee.zip")
        } else {
            check("the source is the zip", false)
        }
        check("a store extension needs no build", !coffee.needsBuild)

        check(
            "a truncated body throws",
            (try? ExtensionStoreResponse.parseStore(Data("{".utf8), registry: .store)) == nil)

        let url = ExtensionStoreResponse.searchURL(query: "co ffee", page: 2)?.absoluteString ?? ""
        check("the query is escaped", url.contains("q=co%20ffee"))
        check("the page is passed", url.contains("page=2"))
        // Tinycast is macOS-only; a windows-only extension is noise.
        check("macOS is requested", url.contains("platform=macos"))
    }

    // MARK: - A GitHub registry

    static func gitHubTree() {
        print("\n# github tree")
        let payload = """
            {"tree":[{"path":"src","type":"tree","sha":"t1"},
                     {"path":"package.json","type":"blob","sha":"b1"},
                     {"path":"src/index.ts","type":"blob","sha":"b2"}],"truncated":false}
            """
        guard let tree = try? ExtensionStoreResponse.parseTree(Data(payload.utf8)) else {
            check("a tree parses", false)
            return
        }
        check("every entry parses", tree.tree.count == 3)
        check("a directory is flagged", tree.tree[0].isDirectory)
        check("a file is flagged", tree.tree[1].isFile)
        check("a directory is not a file", !tree.tree[0].isFile)
        // A recursive listing carries nested paths, which is what makes one call enough.
        check("nested paths survive", tree.tree[2].path == "src/index.ts")
        check("a directory is found by name", tree.directorySHA(named: "src") == "t1")
        check("only directories are named", tree.directoryNames == ["src"])

        // GitHub answers a rate limit or a bad ref with an object where a tree was expected.
        let rejection = #"{"message":"API rate limit exceeded"}"#
        do {
            _ = try ExtensionStoreResponse.parseTree(Data(rejection.utf8))
            check("a rejection throws", false)
        } catch {
            check(
                "a rejection surfaces GitHub's own words",
                error.localizedDescription.contains("rate limit"))
        }

        // A truncated listing is a prefix; installing from it would silently drop files.
        let truncated = #"{"tree":[],"truncated":true}"#
        check(
            "truncation is reported",
            (try? ExtensionStoreResponse.parseTree(Data(truncated.utf8)))?.truncated == true)

        let url =
            ExtensionStoreResponse.treeURL(
                owner: "raycast", repository: "extensions", sha: "abc", recursive: true
            )?.absoluteString ?? ""
        check(
            "the tree URL is built",
            url.hasPrefix("https://api.github.com/repos/raycast/extensions/git/trees/abc"))
        check("recursive is requested", url.contains("recursive=1"))
        check(
            "and omitted otherwise",
            ExtensionStoreResponse.treeURL(owner: "raycast", repository: "extensions", sha: "abc")?
                .absoluteString.contains("recursive") == false)
    }

    static func manifestSummary() {
        print("\n# manifest summary")
        let registry = ExtensionRegistry.officialGitHub
        let manifest = """
            {"name":"coffee","title":"Coffee","description":"Prevent sleep","author":"mooxl",
             "icon":"extension-icon.png","commands":[{"name":"caffeinate"}]}
            """
        guard
            let listing = ExtensionStoreResponse.parseManifestSummary(
                Data(manifest.utf8), folder: "coffee", registry: registry)
        else {
            check("a manifest parses", false)
            return
        }
        check("the title is read", listing.title == "Coffee")
        check("the author is read", listing.author == "mooxl")
        check("commands are counted", listing.commandCount == 1)
        check("no download count is claimed", listing.downloadCount == nil)
        check("source has to be built", listing.needsBuild)
        check(
            "the icon points into the repository",
            listing.iconURL(isDark: true)?.absoluteString
                == "https://raw.githubusercontent.com/raycast/extensions/main/extensions/coffee/assets/extension-icon.png"
        )
        if case .githubFolder(let owner, _, let path, let ref) = listing.source {
            check("the folder is addressed", owner == "raycast" && path == "extensions/coffee")
            check("at the registry's ref", ref == "main")
        } else {
            check("the folder is addressed", false)
        }

        check(
            "a manifest with no name is skipped",
            ExtensionStoreResponse.parseManifestSummary(
                Data(#"{"description":"x"}"#.utf8), folder: "x", registry: registry) == nil)
        check(
            "junk is skipped",
            ExtensionStoreResponse.parseManifestSummary(
                Data("not json".utf8), folder: "x", registry: registry) == nil)
    }

    // MARK: - Package managers

    static func packageManagers() {
        print("\n# package managers")
        check("automatic is first", ExtensionPackageManager.allCases.first == .automatic)
        check(
            "every real manager has an executable",
            ExtensionPackageManager.allCases.filter { $0 != .automatic }
                .allSatisfy { !$0.executableName.isEmpty })
        check(
            "every real manager can install",
            ExtensionPackageManager.allCases.filter { $0 != .automatic }
                .allSatisfy { !$0.installArguments.isEmpty })
        check(
            "every real manager runs the build script",
            ExtensionPackageManager.allCases.filter { $0 != .automatic }
                .allSatisfy { $0.buildArguments == ["run", "build"] })
        // An extension's postinstall is code we never asked to run.
        check(
            "installs skip lifecycle scripts",
            ExtensionPackageManager.allCases.filter { $0 != .automatic }
                .allSatisfy { $0.installArguments.contains("--ignore-scripts") })
        check(
            "the preference order covers every real manager",
            Set(ExtensionPackageManager.preferenceOrder)
                == Set(ExtensionPackageManager.allCases.filter { $0 != .automatic }))
        check("npm is the last resort", ExtensionPackageManager.preferenceOrder.last == .npm)
        check(
            "homebrew is on the search path",
            ExtensionPackageManager.searchPaths.contains("/opt/homebrew/bin"))
        check(
            "so is Intel homebrew",
            ExtensionPackageManager.searchPaths.contains("/usr/local/bin"))
        check(
            "and a version manager's shims",
            ExtensionPackageManager.searchPaths.contains { $0.hasSuffix(".volta/bin") })

        // Resolution reads the real filesystem, so only its shape is asserted here.
        let resolved = ExtensionPackageManager.npm.resolve()
        check(
            "resolution returns the manager it found",
            resolved == nil || resolved?.manager == .npm)
    }

    static func abbreviation() {
        print("\n# download counts")
        check("under a thousand is exact", ExtensionListing.abbreviate(942) == "942")
        check("thousands are k", ExtensionListing.abbreviate(124_218) == "124k")
        check("millions keep a decimal", ExtensionListing.abbreviate(1_240_000) == "1.2M")
        check("big millions don't", ExtensionListing.abbreviate(24_000_000) == "24M")
        check("zero is zero", ExtensionListing.abbreviate(0) == "0")
    }

    // MARK: - Helpers

    static func check(_ description: String, _ condition: Bool) {
        if condition {
            passes += 1
            print("PASS  \(description)")
        } else {
            failures += 1
            print("FAIL  \(description)")
        }
    }
}
