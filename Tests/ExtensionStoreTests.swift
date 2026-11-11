import Foundation

/// The parts of installing from the store or from GitHub that can be checked without a network.
@main
@MainActor
struct ExtensionStoreTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        gitHubSourceParsing()
        gitHubURLs()
        storeResponse()
        gitHubTree()
        packageManagers()
        abbreviation()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - A GitHub source

    static func gitHubSourceParsing() {
        print("\n# github source parsing")

        let plain = ExtensionGitHubSource("https://github.com/someone/coffee")
        check("a repository URL parses", plain?.owner == "someone" && plain?.repository == "coffee")
        check("and builds the root", plain?.path == "")
        check("of the default branch", plain?.ref == ExtensionGitHubSource.defaultRef)

        check("owner/repo alone parses", ExtensionGitHubSource("someone/coffee")?.owner == "someone")
        check("so does www", ExtensionGitHubSource("www.github.com/someone/coffee")?.repository == "coffee")
        check(
            "a clone URL drops its .git",
            ExtensionGitHubSource("https://github.com/someone/coffee.git")?.repository == "coffee")
        check(
            "an SSH remote parses",
            ExtensionGitHubSource("git@github.com:someone/coffee.git")?.repository == "coffee")
        check(
            "a trailing slash, query or fragment is ignored",
            ExtensionGitHubSource("https://github.com/someone/coffee/?tab=readme#install")?.repository
                == "coffee")
        check(
            "a repository name may hold a dot",
            ExtensionGitHubSource("someone/my.extension")?.repository == "my.extension")

        let folder = ExtensionGitHubSource(
            "https://github.com/raycast/extensions/tree/main/extensions/coffee")
        check("a tree link keeps its ref", folder?.ref == "main")
        check("and its folder", folder?.path == "extensions/coffee")

        let branch = ExtensionGitHubSource("github.com/me/repo/tree/dev")
        check("a branch link builds that branch's root", branch?.ref == "dev" && branch?.path == "")

        check("junk is rejected", ExtensionGitHubSource("not a url") == nil)
        check("a bare owner is rejected", ExtensionGitHubSource("raycast") == nil)
        check("another host is rejected", ExtensionGitHubSource("https://gitlab.com/me/repo") == nil)
        check(
            "a file link is rejected",
            ExtensionGitHubSource("github.com/me/repo/blob/main/package.json") == nil)
        check("a tree link needs its ref", ExtensionGitHubSource("me/repo/tree") == nil)

        check(
            "the summary names the folder and ref",
            folder?.summary == "raycast/extensions/extensions/coffee at main")
        check(
            "and says when it follows the default branch",
            plain?.summary == "someone/coffee on its default branch")
    }

    static func gitHubURLs() {
        print("\n# github urls")
        guard let folder = ExtensionGitHubSource("raycast/extensions/tree/main/extensions/coffee"),
            let root = ExtensionGitHubSource("someone/coffee")
        else {
            check("the fixtures parse", false)
            return
        }

        let url = folder.treeURL(sha: "abc", recursive: true)?.absoluteString ?? ""
        check(
            "the tree URL is built",
            url.hasPrefix("https://api.github.com/repos/raycast/extensions/git/trees/abc"))
        check("recursive is requested", url.contains("recursive=1"))
        check(
            "and omitted otherwise",
            folder.treeURL(sha: "abc")?.absoluteString.contains("recursive") == false)

        check(
            "a file in a folder is addressed by ref",
            folder.rawURL(for: "src/index.ts")?.absoluteString
                == "https://raw.githubusercontent.com/raycast/extensions/main/extensions/coffee/src/index.ts")
        check(
            "a file at the root has no empty segment",
            root.rawURL(for: "package.json")?.absoluteString
                == "https://raw.githubusercontent.com/someone/coffee/HEAD/package.json")
        check(
            "a space is escaped",
            root.rawURL(for: "assets/my icon.png")?.absoluteString.hasSuffix("assets/my%20icon.png")
                == true)
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
        guard let listings = try? ExtensionStoreResponse.parseStore(Data(storePayload.utf8)) else {
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
        check(
            "the download is the zip", coffee.downloadURL.absoluteString == "https://example.com/coffee.zip")
        check("the version is read", coffee.commitSHA == "c325a1a")

        check(
            "a truncated body throws",
            (try? ExtensionStoreResponse.parseStore(Data("{".utf8))) == nil)

        let url = ExtensionStoreResponse.searchURL(query: "co ffee", page: 2)?.absoluteString ?? ""
        check("the query is escaped", url.contains("q=co%20ffee"))
        check("the page is passed", url.contains("page=2"))
        // Case-sensitive: "macos" matches only extensions listing no platforms.
        check("macOS is requested, as the endpoint spells it", url.contains("platform=macOS"))

        check(
            "a lookup addresses the handle and name",
            ExtensionStoreResponse.lookupURL(handle: "raycast", name: "github")?.absoluteString
                == "https://www.raycast.com/api/v1/extensions/raycast/github")
        check(
            "a lookup without a handle is refused",
            ExtensionStoreResponse.lookupURL(handle: "", name: "github") == nil)

        let entry = """
            {"id":"abc","name":"coffee","commit_sha":"d4e5","status":"active",
             "download_url":"https://example.com/coffee.zip"}
            """
        check(
            "a lookup's single entry parses",
            (try? ExtensionStoreResponse.parseEntry(Data(entry.utf8)))??.commitSHA == "d4e5")
        let delisted = """
            {"id":"abc","name":"coffee","status":"kill_listed",
             "download_url":"https://example.com/coffee.zip"}
            """
        check(
            "a de-listed lookup offers nothing",
            (try? ExtensionStoreResponse.parseEntry(Data(delisted.utf8))) == .some(nil))
    }

    // MARK: - GitHub trees

    static func gitHubTree() {
        print("\n# github tree")
        let payload = """
            {"tree":[{"path":"src","type":"tree","sha":"t1","mode":"040000"},
                     {"path":"package.json","type":"blob","sha":"b1","mode":"100644"},
                     {"path":"bin/helper","type":"blob","sha":"b2","mode":"100755"},
                     {"path":"src/index.ts","type":"blob","sha":"b3","mode":"100644"}],"truncated":false}
            """
        guard let tree = try? ExtensionGitHubSource.parseTree(Data(payload.utf8)) else {
            check("a tree parses", false)
            return
        }
        check("every entry parses", tree.tree.count == 4)
        check("a directory is flagged", tree.tree[0].isDirectory)
        check("a file is flagged", tree.tree[1].isFile)
        check("a directory is not a file", !tree.tree[0].isFile)
        check("an executable blob keeps its mode", tree.tree[2].isExecutable)
        check("an ordinary blob is not executable", !tree.tree[1].isExecutable)
        // A recursive listing carries nested paths, which is what makes one call enough.
        check("nested paths survive", tree.tree[3].path == "src/index.ts")
        check("a directory is found by name", tree.directorySHA(named: "src") == "t1")
        check("a file is not found as a directory", tree.directorySHA(named: "package.json") == nil)

        // GitHub answers a rate limit or a bad ref with an object where a tree was expected.
        let rejection = #"{"message":"API rate limit exceeded"}"#
        do {
            _ = try ExtensionGitHubSource.parseTree(Data(rejection.utf8))
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
            (try? ExtensionGitHubSource.parseTree(Data(truncated.utf8)))?.truncated == true)
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
