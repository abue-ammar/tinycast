import Foundation

@main
struct ScopesTest {
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("tinycast-scopes-\(UUID().uuidString)")

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func makeDir(_ url: URL) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        func link(_ url: URL, to target: URL) {
            try? fm.createSymbolicLink(at: url, withDestinationURL: target)
        }

        func makeApp(_ url: URL, version: String) {
            let contents = url.appendingPathComponent("Contents")
            makeDir(contents)
            let plist = ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": version]
            let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: contents.appendingPathComponent("Info.plist"))
        }

        func paths(in scopes: [String]) -> [String] {
            SearchScopes.appBundles(in: scopes).map {
                $0.pathComponents.drop(while: { $0 != root.lastPathComponent }).dropFirst()
                    .joined(separator: "/")
            }
        }

        // Two direct apps, a non-app file, a hidden app, one nested app, one two-deep nested app.
        let apps = root.appendingPathComponent("Apps")
        makeDir(apps.appendingPathComponent("Alpha.app"))
        makeDir(apps.appendingPathComponent("Beta.app"))
        makeDir(apps.appendingPathComponent("Notes.txt"))
        makeDir(apps.appendingPathComponent(".Hidden.app"))
        let vendor = apps.appendingPathComponent("Vendor")
        makeDir(vendor.appendingPathComponent("Nested.app"))
        let deep = vendor.appendingPathComponent("Deeper")
        makeDir(deep.appendingPathComponent("TooDeep.app"))

        let found = SearchScopes.appBundles(in: [apps.path]).map(\.lastPathComponent)
        check(
            "direct and one-level-nested .app children are indexed",
            Set(found) == ["Alpha.app", "Beta.app", "Nested.app"])
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        check("bundles nested two levels deep are not indexed", !found.contains("TooDeep.app"))
        check(
            "a deeply nested folder works as its own scope",
            SearchScopes.appBundles(in: [deep.path]).map(\.lastPathComponent) == ["TooDeep.app"])

        // A linked scope must keep its logical paths, including children and alternate aliases.
        let scopeLink = root.appendingPathComponent("LinkedApps")
        link(scopeLink, to: apps)
        let expectedLinkedPaths = [
            "LinkedApps/Alpha.app", "LinkedApps/Beta.app", "LinkedApps/Vendor/Nested.app"
        ]
        check(
            "a symlinked directory scope preserves its paths",
            paths(in: [scopeLink.path]) == expectedLinkedPaths)
        check(
            "a scope under a linked parent keeps its configured spelling",
            SearchScopes.appBundles(in: [apps.path]).allSatisfy { $0.path.hasPrefix(apps.path + "/") })
        let scopeChain = root.appendingPathComponent("LinkedAgain")
        link(scopeChain, to: scopeLink)
        check(
            "directory symlink chains preserve the configured scope",
            paths(in: [scopeChain.path])
                == ["LinkedAgain/Alpha.app", "LinkedAgain/Beta.app", "LinkedAgain/Vendor/Nested.app"])
        check(
            "separate scopes retain their aliases in scope order",
            paths(in: [scopeLink.path, apps.path]) == expectedLinkedPaths + paths(in: [apps.path]))

        // A stable scope path must pick up a changed symlink target without reconfiguration.
        let replacement = root.appendingPathComponent("Replacement")
        makeDir(replacement.appendingPathComponent("Updated.app"))
        try? fm.removeItem(at: scopeChain)
        link(scopeChain, to: replacement)
        check(
            "a retargeted directory link uses its new contents on the next scan",
            paths(in: [scopeChain.path]) == ["LinkedAgain/Updated.app"])

        // App links remain leaves; folder links keep the same visibility and depth limits.
        let links = root.appendingPathComponent("Links")
        makeDir(links)
        let appLink = links.appendingPathComponent("Renamed.app")
        link(appLink, to: apps.appendingPathComponent("Alpha.app"))
        check(
            "an app symlink is indexed with its own name and path",
            paths(in: [links.path]) == ["Links/Renamed.app"])
        check(
            "an app symlink works as its own scope",
            paths(in: [appLink.path]) == ["Links/Renamed.app"])
        let vendorLink = links.appendingPathComponent("Vendor")
        link(vendorLink, to: vendor)
        link(links.appendingPathComponent(".HiddenVendor"), to: vendor)
        link(links.appendingPathComponent("Missing"), to: root.appendingPathComponent("Nope"))
        check(
            "symlinked subfolders preserve paths without indexing hidden or deeper children",
            paths(in: [links.path]) == ["Links/Renamed.app", "Links/Vendor/Nested.app"])
        link(links.appendingPathComponent("Back"), to: links)
        let cycle = links.appendingPathComponent("Cycle")
        link(cycle, to: cycle)
        check("a cyclic directory scope is skipped", SearchScopes.appBundles(in: [cycle.path]).isEmpty)
        check(
            "ancestor and cyclic directory links do not loop or hide other apps",
            SearchScopes.appBundles(in: [links.path]).count == 2)

        // Cycle detection is per ancestry, so sibling links must not suppress each other.
        link(links.appendingPathComponent("OtherVendor"), to: vendor)
        check(
            "sibling links to one directory retain both logical paths",
            paths(in: [links.path])
                == ["Links/OtherVendor/Nested.app", "Links/Renamed.app", "Links/Vendor/Nested.app"])

        // A scope may be a single bundle: that is how Finder ships as a default.
        check(
            "an .app scope is indexed directly",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Alpha.app").path])
                .map(\.lastPathComponent) == ["Alpha.app"])
        check(
            "a missing .app scope yields nothing",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Gone.app").path]).isEmpty)
        check(
            "a missing directory scope is skipped without failing the rest",
            SearchScopes.appBundles(in: [root.appendingPathComponent("Nope").path, deep.path])
                .map(\.lastPathComponent) == ["TooDeep.app"])

        // Xcode ships Instruments and Simulator inside its own bundle.
        let tools = root.appendingPathComponent("Tools")
        let xcode = tools.appendingPathComponent("Xcode.app")
        makeDir(xcode.appendingPathComponent("Contents/Applications/Instruments.app"))
        makeDir(xcode.appendingPathComponent("Contents/Developer/Applications/Simulator.app"))
        makeDir(xcode.appendingPathComponent("Contents/Frameworks/Helper.app"))
        let embedded = Set(SearchScopes.appBundles(in: [tools.path]).map(\.lastPathComponent))
        check(
            "apps embedded in a bundle's application folders are indexed",
            embedded == ["Xcode.app", "Instruments.app", "Simulator.app"])
        check(
            "an .app scope also yields its embedded apps",
            Set(SearchScopes.appBundles(in: [xcode.path]).map(\.lastPathComponent)) == embedded)

        // Embedded application folders can be links without changing the indexed paths.
        let linkedHost = root.appendingPathComponent("LinkedHost.app")
        makeDir(linkedHost.appendingPathComponent("Contents"))
        link(linkedHost.appendingPathComponent("Contents/Applications"), to: tools)
        check(
            "symlinked embedded-app folders preserve paths",
            paths(in: [linkedHost.path]).contains("LinkedHost.app/Contents/Applications/Xcode.app"))

        // An embedded app link can point back to its host, so traversal must stop at the ancestor.
        let loopHost = root.appendingPathComponent("LoopHost.app")
        let loopFolder = loopHost.appendingPathComponent("Contents/Applications")
        makeDir(loopFolder)
        link(loopFolder.appendingPathComponent("Back.app"), to: loopHost)
        check(
            "embedded app symlinks cannot recurse into an ancestor folder",
            SearchScopes.appBundles(in: [loopHost.path]).map(\.lastPathComponent)
                == ["LoopHost.app", "Back.app"])

        func listing(_ folder: String, versions: [String: String]) -> [String] {
            let url = root.appendingPathComponent(folder)
            for (name, version) in versions {
                makeApp(url.appendingPathComponent(name), version: version)
            }
            return SearchScopes.appBundles(in: [url.path]).map(\.lastPathComponent)
        }

        // Mirrored names, so no fixed filesystem order can pass both checks by luck.
        check(
            "a folder lists its newest version first, compared as numbers",
            listing("Rising", versions: ["A.app": "9.4", "B.app": "26.6", "C.app": "27.0"])
                == ["C.app", "B.app", "A.app"])
        check(
            "the newest version leads whatever its name",
            listing("Falling", versions: ["A.app": "27.0", "B.app": "26.6", "C.app": "9.4"])
                == ["A.app", "B.app", "C.app"])

        check(
            "equal versions fall back to Finder's name order",
            listing("Ties", versions: ["Xcode-beta.app": "26.0", "Xcode.app": "26.0"])
                == ["Xcode.app", "Xcode-beta.app"])

        // Preserving logical paths must not prevent reading bundle versions through the link.
        let versionLink = root.appendingPathComponent("Versions")
        link(versionLink, to: root.appendingPathComponent("Rising"))
        check(
            "a linked directory still lists its newest app version first",
            paths(in: [versionLink.path]) == ["Versions/C.app", "Versions/B.app", "Versions/A.app"])

        let unreadable = root.appendingPathComponent("Unreadable")
        makeDir(unreadable.appendingPathComponent("Aardvark.app"))
        makeApp(unreadable.appendingPathComponent("Zebra.app"), version: "1.0")
        check(
            "a bundle with no version sorts after one that has a version",
            SearchScopes.appBundles(in: [unreadable.path]).map(\.lastPathComponent)
                == ["Zebra.app", "Aardvark.app"])

        check(
            "an earlier scope still wins over a newer version in a later one",
            SearchScopes.appBundles(in: [
                root.appendingPathComponent("Rising/A.app").path,
                root.appendingPathComponent("Rising").path
            ]).map(\.lastPathComponent).first == "A.app")

        check(
            "scopes are scanned in order",
            SearchScopes.appBundles(in: [deep.path, apps.path]).map(\.lastPathComponent).first
                == "TooDeep.app")
        check(
            "overlapping scopes yield each app once, at its first scope's position",
            SearchScopes.appBundles(in: [xcode.path, tools.path, deep.path, vendor.path])
                .map(\.lastPathComponent)
                == ["Xcode.app", "Instruments.app", "Simulator.app", "TooDeep.app", "Nested.app"])

        let home = fm.homeDirectoryForCurrentUser.path
        check(
            "expand resolves a tilde",
            SearchScopes.expand("~/Applications") == home + "/Applications")
        check(
            "abbreviate restores the tilde",
            SearchScopes.abbreviate(home + "/Applications") == "~/Applications")
        check(
            "tilde survives a round trip",
            SearchScopes.abbreviate(SearchScopes.expand("~/Applications")) == "~/Applications")
        check(
            "expand leaves an absolute path alone",
            SearchScopes.expand("/Applications") == "/Applications")
        check(
            "a trailing slash is trimmed",
            SearchScopes.abbreviate("/Applications/") == "/Applications")
        check("root survives trimming", SearchScopes.abbreviate("/") == "/")

        check(
            "normalize dedups after abbreviating",
            SearchScopes.normalize([
                "/Applications", "/Applications/", home + "/Applications", "~/Applications"
            ])
                == ["/Applications", "~/Applications"])
        check("normalize preserves order", SearchScopes.normalize(["/B", "/A"]) == ["/B", "/A"])
        check("normalize drops blanks", SearchScopes.normalize(["  ", "/A"]) == ["/A"])
        check(
            "defaults are already normalized",
            SearchScopes.normalize(SearchScopes.defaults) == SearchScopes.defaults)

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
