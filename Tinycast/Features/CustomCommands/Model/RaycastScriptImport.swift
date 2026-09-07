import Foundation

/// Reads a folder of Raycast script commands into drafts. See docs/features/custom-commands.md.
enum RaycastScriptImport {
    private static let headSize = 8 * 1024
    private static let directivePrefix = "@raycast."
    /// `#` for the shell templates, `//` for JavaScript and Swift, `--` for AppleScript.
    private static let commentMarkers = ["#", "//", "--"]

    /// Non-recursive, like Raycast's own script directories; a non-command file is skipped.
    nonisolated static func scan(
        directory: URL, fileManager: FileManager = .default
    ) -> [CustomCommand] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return
            contents
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                    let source = head(of: url)
                else { return nil }
                return command(at: url, source: source)
            }
    }

    /// A file is a script command when it names an interpreter and declares a title.
    nonisolated static func command(at url: URL, source: String) -> CustomCommand? {
        guard let interpreter = shebang(in: source) else { return nil }
        let directives = directives(in: source)
        guard let title = directives["title"] else { return nil }
        // The runner's values land on zsh's positional list; unforwarded, the script sees none.
        return CustomCommand(
            name: title,
            command: "\(interpreter) \(shellQuoted(url.path)) \"$@\"",
            requiresConfirmation: directives["needsConfirmation"] == "true",
            arguments: arguments(in: directives),
            showsOutput: showsOutput(mode: directives["mode"]),
            workingDirectory: workingDirectory(directives["currentDirectoryPath"], script: url))
    }

    /// Raycast requires one, and naming it rather than relying on the exec bit leaves the file be.
    private static func shebang(in source: String) -> String? {
        let first = source.prefix { !$0.isNewline }
        guard first.hasPrefix("#!") else { return nil }
        let interpreter = first.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        return interpreter.isEmpty ? nil : interpreter
    }

    /// The block ends where the code starts; past that, `@raycast.` is the script's own text.
    private static func directives(in source: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let body = commentBody(trimmed) else { break }
            guard body.hasPrefix(directivePrefix) else { continue }
            let field = body.dropFirst(directivePrefix.count)
            guard let separator = field.firstIndex(where: \.isWhitespace) else { continue }
            let key = String(field[..<separator])
            let value = field[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    private static func commentBody(_ line: String) -> String? {
        guard let marker = commentMarkers.first(where: line.hasPrefix) else { return nil }
        return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    /// `silent` and `inline` have nothing to show; the two output modes open the window.
    private static func showsOutput(mode: String?) -> Bool {
        mode == "compact" || mode == "fullOutput"
    }

    /// Raycast allows three, each a JSON object whose placeholder is what we prompt with.
    private static func arguments(in directives: [String: String]) -> [CustomCommandArgument] {
        (1...3).compactMap { index in
            guard let json = directives["argument\(index)"]?.data(using: .utf8),
                let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
                let placeholder = object["placeholder"] as? String, !placeholder.isEmpty
            else { return nil }
            return CustomCommandArgument(
                name: placeholder, isOptional: object["optional"] as? Bool ?? false)
        }
    }

    /// The script's own folder unless it says otherwise, which is what its relative paths mean.
    private static func workingDirectory(_ declared: String?, script: URL) -> String {
        let path = declared ?? script.deletingLastPathComponent().path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    /// Single-quoted, so a path holding a space, a `$` or a quote is still one word to zsh.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The shebang and the directives are at the top, and a body running to megabytes is not.
    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var data = try? handle.read(upToCount: headSize), !data.isEmpty else { return nil }
        // Cut at a newline, which no multi-byte character contains: a full read lands mid-line.
        if data.count == headSize, let end = data.lastIndex(of: UInt8(ascii: "\n")) {
            data = data[..<end]
        }
        return String(bytes: data, encoding: .utf8)
    }
}
