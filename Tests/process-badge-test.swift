import Foundation

/// `p_comm` comes from the basename of the exec'd file, so the link's name is the whole mechanism.
@main
@MainActor
struct ProcessBadgeTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool) {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    /// Rebuilt each time: Foundation caches resource values, so a held `URL` reports a stale inode.
    static func identifier(_ url: URL) -> NSObject? {
        try? URL(fileURLWithPath: url.path)
            .resourceValues(forKeys: [.fileResourceIdentifierKey])
            .fileResourceIdentifier as? NSObject
    }

    /// Two paths naming one file, which is what a hard link is.
    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        guard let x = identifier(a), let y = identifier(b) else { return false }
        return x == y
    }

    static func main() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("badge-\(UUID().uuidString)")
        let links = root.appendingPathComponent("Processes")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A real binary on the same volume, which is the case the badge exists for.
        let binary = root.appendingPathComponent("node")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: binary)

        print("# a real binary gets a named hard link")
        let badged = ProcessBadge.badged(binary, in: links)
        check("the link is named for Tinycast", badged.lastPathComponent == "Tinycast (node)")
        check(
            "the link is under the badge directory",
            badged.standardizedFileURL.path.hasPrefix(links.standardizedFileURL.path + "/"))
        check("the link is the same file", sameFile(badged, binary))
        check("the name fits p_comm", badged.lastPathComponent.utf8.count <= ProcessBadge.nameLimit)

        print("\n# a second call reuses it")
        check("the same link comes back", ProcessBadge.badged(binary, in: links) == badged)

        print("\n# two interpreters sharing a basename get their own link")
        let other = root.appendingPathComponent("other")
        try? FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let rival = other.appendingPathComponent("node")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/date"), to: rival)
        let rivalLink = ProcessBadge.badged(rival, in: links)
        check("both are badged", rivalLink.lastPathComponent == "Tinycast (node)")
        check("but not to the same path", rivalLink != ProcessBadge.badged(binary, in: links))
        check("each links its own interpreter", sameFile(rivalLink, rival))
        check(
            "and the first one still points where it did",
            sameFile(ProcessBadge.badged(binary, in: links), binary))

        print("\n# the link follows the interpreter")
        try? FileManager.default.removeItem(at: binary)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/date"), to: binary)
        let remade = ProcessBadge.badged(binary, in: links)
        check("an upgraded interpreter is relinked", sameFile(remade, binary))

        print("\n# an upgrade of one doesn't disturb the other")
        check(
            "the upgraded one still resolves to itself",
            sameFile(ProcessBadge.badged(binary, in: links), binary))
        check(
            "and its rival is untouched", sameFile(ProcessBadge.badged(rival, in: links), rival))

        print("\n# installing a badge leaves nothing behind")
        let digest = ProcessBadge.digest(binary.resolvingSymlinksInPath().path)
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                atPath: links.appendingPathComponent(digest).path)) ?? []
        check("only the link is in its directory", contents == ["Tinycast (node)"])

        print("\n# a binary that resolves libraries from its own path keeps it")
        // A thin 64-bit header, then a load-command region of the size the header declares.
        func machO(commands: String) -> Data {
            var header = Data([0xcf, 0xfa, 0xed, 0xfe])
            header.append(Data(repeating: 0, count: 16))
            var size = UInt32(commands.utf8.count)
            withUnsafeBytes(of: &size) { header.append(contentsOf: $0) }
            header.append(Data(repeating: 0, count: 8))
            return header + Data(commands.utf8)
        }
        let plain = root.appendingPathComponent("plain")
        try? machO(commands: String(repeating: "\0", count: 64)).write(to: plain)
        check("a binary with no such load command is fine", !ProcessBadge.dependsOnItsOwnPath(plain))

        let relative = root.appendingPathComponent("relative")
        try? machO(commands: "@executable_path/../lib\0\0").write(to: relative)
        check("one naming @executable_path is not", ProcessBadge.dependsOnItsOwnPath(relative))
        check("so it is never badged", ProcessBadge.badged(relative, in: links) == relative)

        let loader = root.appendingPathComponent("loader")
        try? machO(commands: "@loader_path/../lib\0\0").write(to: loader)
        check("nor is one naming @loader_path", ProcessBadge.dependsOnItsOwnPath(loader))

        let text = root.appendingPathComponent("notmacho")
        try? Data("just some bytes".utf8).write(to: text)
        check("anything this can't parse is left alone", ProcessBadge.dependsOnItsOwnPath(text))

        print("\n# everything else is left alone")
        let script = root.appendingPathComponent("npm")
        try? Data("#!/bin/sh\necho hi\n".utf8).write(to: script)
        check(
            "a shebang script is not badged, since it re-execs its interpreter",
            ProcessBadge.badged(script, in: links) == script)

        let long = root.appendingPathComponent("interpreter-with-a-long-name")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: long)
        check(
            "a name past the p_comm cap is not badged",
            ProcessBadge.badged(long, in: links) == long)
        check(
            "a name exactly at the cap is badged, measured against p_comm",
            ProcessBadge.badgeName(for: URL(fileURLWithPath: "/x/codex")).utf8.count
                == ProcessBadge.nameLimit)

        print("\n# the badge is named for the command, not what it resolves to")
        let release = root.appendingPathComponent("grok-macos-aarch64")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: release)
        let invoked = root.appendingPathComponent("grok")
        try? FileManager.default.createSymbolicLink(at: invoked, withDestinationURL: release)
        let grok = ProcessBadge.badged(invoked, in: links)
        check("the symlink's own name is used", grok.lastPathComponent == "Tinycast (grok)")
        check("and it links the file the symlink points at", sameFile(grok, release))

        let missing = root.appendingPathComponent("not-here")
        check(
            "a path that isn't there is left alone",
            ProcessBadge.badged(missing, in: links) == missing)

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
