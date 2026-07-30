import Foundation

/// Drives the real `AppLeftovers` against a throwaway home directory, so a run can never see — let
/// alone return — a path in the developer's own Library.
@main
struct LeftoversTest {
    static func main() {
        let fm = FileManager.default
        let home = fm.temporaryDirectory
            .appendingPathComponent("tinycast-leftovers-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func makeDir(_ relative: String) -> URL {
            let url = home.appendingPathComponent(relative)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func makeFile(_ relative: String, bytes: Int = 8) -> URL {
            let url = home.appendingPathComponent(relative)
            try? fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: bytes))
            return url
        }

        /// The temp home lives under `/var`, a symlink to `/private/var`, and a directory listing
        /// resolves it while a constructed path doesn't — so every comparison here goes through one
        /// canonical form. A real home (`/Users/…`) has no such symlink.
        func canon(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

        func paths(
            name: String = "Acme Studio", bundleID: String? = "com.acme.studio",
            sibling: Bool = false
        ) -> Set<String> {
            Set(
                AppLeftovers.supportPaths(
                    appName: name, bundleID: bundleID, home: home, siblingBundleExists: sibling
                ).map(canon))
        }

        // MARK: Eligibility

        check(
            "a normal app is eligible",
            AppLeftovers.canUninstall(
                url: URL(fileURLWithPath: "/Applications/Acme.app"), bundleID: "com.acme.studio"))
        check(
            "an app with no bundle id is still eligible",
            AppLeftovers.canUninstall(
                url: URL(fileURLWithPath: "/Applications/Acme.app"), bundleID: nil))
        check(
            "system apps are refused",
            !AppLeftovers.canUninstall(
                url: URL(fileURLWithPath: "/System/Applications/Mail.app"),
                bundleID: "com.apple.mail"))
        // Refused by bundle id, not just by path: the cryptex-delivered apps report a `/System/Volumes/…`
        // location, and an Apple app copied anywhere else is still Apple's.
        check(
            "Apple bundle ids are refused wherever they live (cryptex Safari)",
            !AppLeftovers.canUninstall(
                url: URL(
                    fileURLWithPath:
                        "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"),
                bundleID: "com.apple.Safari")
                && !AppLeftovers.canUninstall(
                    url: URL(fileURLWithPath: "/Applications/Safari.app"),
                    bundleID: "com.apple.Safari")
        )
        check(
            "Tinycast refuses to uninstall itself",
            !AppLeftovers.canUninstall(
                url: URL(fileURLWithPath: "/Applications/Tinycast.app"),
                bundleID: "com.tinycast.app"))
        check(
            "every Tinycast channel is refused",
            !AppLeftovers.canUninstall(
                url: URL(fileURLWithPath: "/Users/x/build/Tinycast Dev.app"),
                bundleID: "com.tinycast.app.dev"))
        check(
            "a non-bundle path is refused",
            !AppLeftovers.canUninstall(
                url: URL(fileURLWithPath: "/Applications/Acme"), bundleID: "com.acme.studio"))

        // MARK: Bundle-id keyed discovery

        let container = makeDir("Library/Containers/com.acme.studio")
        let httpStorages = makeDir("Library/HTTPStorages/com.acme.studio")
        let cookies = makeFile("Library/HTTPStorages/com.acme.studio.binarycookies")
        let prefs = makeFile("Library/Preferences/com.acme.studio.plist")
        let byHost = makeFile("Library/Preferences/ByHost/com.acme.studio.ABC-123.plist")
        let agent = makeFile("Library/LaunchAgents/com.acme.studio.plist")
        let helperAgent = makeFile("Library/LaunchAgents/com.acme.studio.updater.plist")
        let groupContainer = makeDir("Library/Group Containers/5HD2ARTBFS.com.acme.studio")
        let helperContainer = makeDir("Library/Containers/com.acme.studio.helper")
        let webKit = makeDir("Library/WebKit/com.acme.studio")
        let sessionDownloads = makeDir(
            "Library/Caches/com.apple.nsurlsessiond/Downloads/com.acme.studio")

        let found = paths()
        for url in [
            container, httpStorages, cookies, prefs, byHost, agent, helperAgent, groupContainer,
            helperContainer, webKit, sessionDownloads,
        ] {
            check("finds \(url.lastPathComponent)", found.contains(canon(url)))
        }

        // MARK: Name-keyed discovery and its variants

        let support = makeDir("Library/Application Support/Acme Studio")
        let nospaceCaches = makeDir("Library/Caches/AcmeStudio")
        let hyphenLogs = makeDir("Library/Logs/Acme-Studio")
        let underscoreSupport = makeDir("Library/Application Support/Acme_Studio")
        let savedState = makeDir("Library/Saved Application State/Acme Studio.savedState")
        let named = paths()
        for url in [support, nospaceCaches, hyphenLogs, underscoreSupport, savedState] {
            check("finds \(url.lastPathComponent) by name", named.contains(canon(url)))
        }

        // MARK: Non-matches

        let other = makeDir("Library/Application Support/Acme Studio Pro")
        let otherBundle = makeDir("Library/Containers/com.acme.studiopro")
        let unrelatedAgent = makeFile("Library/LaunchAgents/com.other.tool.plist")
        let siblingGroup = makeDir("Library/Group Containers/5HD2ARTBFS.com.other.tool")
        let strict = paths()
        check("a longer neighbouring name isn't matched", !strict.contains(canon(other)))
        check(
            "a bundle id without a dot boundary isn't matched", !strict.contains(canon(otherBundle))
        )
        check("an unrelated launch agent is left alone", !strict.contains(canon(unrelatedAgent)))
        check(
            "another vendor's group container is left alone", !strict.contains(canon(siblingGroup)))
        check(
            "documents are never in scope",
            paths(name: "Documents", bundleID: nil).isEmpty)

        // MARK: Guards

        check(
            "a surviving sibling install drops every keyed path",
            paths(sibling: true).isEmpty)
        check(
            "a two-letter name matches nothing",
            paths(name: "Go", bundleID: nil).isEmpty)
        check(
            "a bundle id with a path separator is refused",
            paths(name: "x", bundleID: "../../etc").isEmpty)
        check(
            "a bundle id with a glob metacharacter is refused",
            paths(name: "x", bundleID: "com.acme.*").isEmpty)
        check(
            "a bundle id without a dot is refused",
            paths(name: "x", bundleID: "acme").isEmpty)
        check(
            "no result is ever a Library root itself",
            paths().allSatisfy {
                !$0.hasSuffix("/Library/Caches") && !$0.hasSuffix("/Library/Preferences")
                    && !$0.hasSuffix("/Library/Containers")
                    && !$0.hasSuffix("/Library/Application Support")
            })
        check(
            "every result stays inside the home directory",
            paths().allSatisfy { $0.hasPrefix(canon(home) + "/Library/") })
        check(
            "results are unique",
            {
                let list = AppLeftovers.supportPaths(
                    appName: "Acme Studio", bundleID: "com.acme.studio", home: home)
                return Set(list.map(\.path)).count == list.count
            }())

        // MARK: Sizing

        _ = makeFile("Library/Caches/com.acme.studio/blob.bin", bytes: 4096)
        let fileSize = AppLeftovers.size(of: prefs)
        let dirSize = AppLeftovers.size(
            of: home.appendingPathComponent("Library/Caches/com.acme.studio"))
        check("a file reports a size", (fileSize ?? 0) > 0)
        check("a directory sums its contents", (dirSize ?? 0) >= 4096)
        check(
            "a missing path has no size",
            AppLeftovers.size(of: home.appendingPathComponent("Library/Caches/gone")) == nil)

        // A symlink must never be sized through: a cask's /Applications alias points at the bundle that
        // is already its own row, so following it would count the same gigabytes twice.
        let linkTarget = makeDir("Library/Caches/com.acme.studio")
        _ = makeFile("Library/Caches/com.acme.studio/big.bin", bytes: 8192)
        let link = home.appendingPathComponent("Library/Caches/com.acme.studio.alias")
        try? fm.createSymbolicLink(at: link, withDestinationURL: linkTarget)
        check("a symlink reports no size", AppLeftovers.size(of: link) == nil)
        check(
            "the symlink's target still measures normally",
            (AppLeftovers.size(of: linkTarget) ?? 0) >= 8192)
        // And removing the link leaves the target alone — the reason the link gets its own row at all.
        check(
            "removing a symlink doesn't touch its target",
            AppLeftovers.remove([link], permanently: true).isEmpty
                && !fm.fileExists(atPath: link.path)
                && fm.fileExists(atPath: linkTarget.path))

        // MARK: Removability (locked rows)

        check(
            "Tinycast's own channels are refused",
            !AppLeftovers.canUninstall(
                url: URL(fileURLWithPath: "/Applications/Tinycast.app"),
                bundleID: "com.tinycast.app")
                && !AppLeftovers.canUninstall(
                    url: URL(fileURLWithPath: "/x/Tinycast Beta.app"),
                    bundleID: "com.tinycast.app.beta")
        )
        check(
            "a protected vendor is recognised, and nobody else is",
            AppLeftovers.isProtectedVendor(bundleID: "com.apple.Photos")
                && !AppLeftovers.isProtectedVendor(bundleID: "com.acme.studio")
                && !AppLeftovers.isProtectedVendor(bundleID: nil))

        let ordinary = makeFile("Library/Caches/com.acme.studio/ordinary.bin")
        check("an ordinary file is removable", AppLeftovers.isRemovable(ordinary))
        check(
            "a path that doesn't exist isn't removable",
            !AppLeftovers.isRemovable(home.appendingPathComponent("Library/Caches/nope")))

        // `chflags uchg` is settable without root, so the immutable branch is exercised for real.
        let immutable = makeFile("Library/Caches/com.acme.studio/immutable.bin")
        _ = try? Process.run(
            URL(fileURLWithPath: "/usr/bin/chflags"), arguments: ["uchg", immutable.path]
        ).waitUntilExit()
        check("an immutable file is not removable", !AppLeftovers.isRemovable(immutable))
        _ = try? Process.run(
            URL(fileURLWithPath: "/usr/bin/chflags"), arguments: ["nouchg", immutable.path]
        ).waitUntilExit()
        check("clearing the flag makes it removable again", AppLeftovers.isRemovable(immutable))

        // A read-only parent is what protects /System and anything root owns.
        let sealedDir = makeDir("Library/Caches/com.acme.studio/sealed")
        let sealedChild = makeFile("Library/Caches/com.acme.studio/sealed/child.bin")
        try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: sealedDir.path)
        check(
            "a file under a read-only parent is not removable",
            !AppLeftovers.isRemovable(sealedChild))
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealedDir.path)

        check(
            "a locked row is what the item carries, not something the view decides",
            LeftoverItem(url: ordinary, kind: .support, size: nil, isRemovable: false).isRemovable
                == false)

        // MARK: Display

        check(
            "a support path renders tilde-abbreviated",
            LeftoverItem(
                url: URL(fileURLWithPath: fm.homeDirectoryForCurrentUser.path)
                    .appendingPathComponent("Library/Caches/com.acme.studio"),
                kind: .support, size: nil
            ).displayPath == "~/Library/Caches/com.acme.studio")
        check(
            "a path outside home keeps its absolute form",
            LeftoverItem(
                url: URL(fileURLWithPath: "/Applications/Acme Studio.app"), kind: .bundle, size: nil
            ).displayPath == "/Applications/Acme Studio.app")

        // MARK: Removal
        //
        // The permanent path is exercised for real against fixtures. The trash path is too — on a file
        // whose name carries this run's UUID, and the trashed copy is hunted down and deleted
        // afterwards, so a test run never leaves litter in the developer's Trash.

        let doomedFile = makeFile("Library/Caches/com.acme.studio/doomed.bin")
        let doomedTree = makeDir("Library/Application Support/Acme Studio/nested/deeper")
        _ = makeFile("Library/Application Support/Acme Studio/nested/deeper/leaf.bin")
        let doomedTreeRoot = home.appendingPathComponent("Library/Application Support/Acme Studio")

        check(
            "permanent removal reports no failures",
            AppLeftovers.remove([doomedFile], permanently: true).isEmpty)
        check("permanent removal erases the file", !fm.fileExists(atPath: doomedFile.path))
        check(
            "permanent removal takes a whole tree",
            AppLeftovers.remove([doomedTreeRoot], permanently: true).isEmpty
                && !fm.fileExists(atPath: doomedTree.path)
                && !fm.fileExists(atPath: doomedTreeRoot.path))

        let missing = home.appendingPathComponent("Library/Caches/never-existed")
        check(
            "a missing path is reported as a failure",
            AppLeftovers.remove([missing], permanently: true) == [missing.path])

        // One failure must not strand the rest: a root-owned bundle shouldn't leave its support files behind.
        let survivor = makeFile("Library/Caches/com.acme.studio/after-failure.bin")
        let mixed = AppLeftovers.remove([missing, survivor], permanently: true)
        check("removal continues past a failure", mixed == [missing.path])
        check("the item after a failure is gone", !fm.fileExists(atPath: survivor.path))

        let trashName = "tinycast-trash-probe-\(UUID().uuidString).bin"
        let trashed = makeFile("Library/Caches/com.acme.studio/" + trashName)
        check(
            "trashing reports no failures",
            AppLeftovers.remove([trashed], permanently: false).isEmpty
        )
        check("trashing removes the original", !fm.fileExists(atPath: trashed.path))

        // The one assertion that actually distinguishes trashing from unlinking — the original is gone
        // either way. Reading ~/.Trash needs Full Disk Access, which a plain shell doesn't have, so
        // this reports as skipped rather than failing on a permission the harness can't grant itself.
        let trashDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        if let entries = try? fm.contentsOfDirectory(atPath: trashDir.path) {
            let landed = entries.first { $0 == trashName || $0.hasPrefix(trashName) }
            check("trashing puts the item in the Trash, not the void", landed != nil)
            // Leave no litter behind: the trashed fixture is deleted for real.
            if let landed { try? fm.removeItem(at: trashDir.appendingPathComponent(landed)) }
        } else {
            print(
                "SKIP  trashing puts the item in the Trash — ~/.Trash unreadable (Full Disk Access)"
            )
            // Best-effort tidy at the path macOS uses, in case the read was the only thing blocked.
            try? fm.removeItem(at: trashDir.appendingPathComponent(trashName))
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
