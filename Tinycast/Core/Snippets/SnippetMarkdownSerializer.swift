import Foundation

struct SnippetMarkdownSerializer {
    enum ParseError: Error, LocalizedError, Equatable {
        case invalidFrontmatter(fileURL: URL, line: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .invalidFrontmatter(let fileURL, let line, let reason):
                return "\(fileURL.path):\(line): \(reason)"
            }
        }
    }

    static func parse(content: String, fileURL: URL) throws -> Snippet {
        let lines = sourceLines(in: content)
        guard lines.first?.text == "---" else {
            return Snippet(name: defaultName(for: fileURL), text: content)
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0.text == "---" }) else {
            throw parseError(fileURL, line: 1, "Missing closing frontmatter delimiter")
        }

        var name: String?
        var keyword: String?
        var category: String?
        var isEnabled = true
        var showInLauncher = true
        var showHUD = false
        var seenKeys = Set<String>()

        for lineIndex in 1..<closingIndex {
            let line = lines[lineIndex]
            let lineNumber = lineIndex + 1
            guard !line.text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let separator = line.text.firstIndex(of: ":") else {
                throw parseError(fileURL, line: lineNumber, "Expected a key and value separated by ':'")
            }

            let rawKey = line.text[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line.text[line.text.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard let key = canonicalKey(for: rawKey) else {
                throw parseError(fileURL, line: lineNumber, "Unsupported frontmatter key '\(rawKey)'")
            }
            guard seenKeys.insert(key).inserted else {
                throw parseError(fileURL, line: lineNumber, "Duplicate frontmatter key '\(key)'")
            }

            switch key {
            case "name":
                let decoded = try decodeScalar(rawValue, fileURL: fileURL, line: lineNumber)
                // A blank name is treated as absent so the filename fallback still yields something selectable.
                name = decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : decoded
            case "keyword":
                keyword = try decodeScalar(rawValue, fileURL: fileURL, line: lineNumber)
            case "category":
                category = try decodeScalar(rawValue, fileURL: fileURL, line: lineNumber)
            case "enabled":
                isEnabled = try decodeBoolean(rawValue, fileURL: fileURL, line: lineNumber)
            case "show_in_launcher":
                showInLauncher = try decodeBoolean(rawValue, fileURL: fileURL, line: lineNumber)
            case "show_hud":
                showHUD = try decodeBoolean(rawValue, fileURL: fileURL, line: lineNumber)
            default:
                preconditionFailure("Canonical keys are exhaustively handled")
            }
        }

        let bodyStart = lines[closingIndex].endIncludingTerminator
        return Snippet(
            name: name ?? defaultName(for: fileURL),
            text: String(content[bodyStart...]),
            keyword: keyword,
            category: category,
            isEnabled: isEnabled,
            showInLauncher: showInLauncher,
            showHUD: showHUD
        )
    }

    static func serialize(_ snippet: Snippet) -> String {
        var lines = [
            "---",
            "name: \(encodeScalar(snippet.name))",
        ]
        if let keyword = snippet.keyword {
            lines.append("keyword: \(encodeScalar(keyword))")
        }
        if let category = snippet.category {
            lines.append("category: \(encodeScalar(category))")
        }
        lines.append("enabled: \(snippet.isEnabled)")
        lines.append("show_in_launcher: \(snippet.showInLauncher)")
        lines.append("show_hud: \(snippet.showHUD)")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + snippet.text
    }

    static func slug(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var slug = name.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        if slug.isEmpty { slug = "snippet" }
        return slug
    }

    private struct SourceLine {
        let text: Substring
        let endIncludingTerminator: String.Index
    }

    private static func sourceLines(in content: String) -> [SourceLine] {
        var lines: [SourceLine] = []
        var lineStart = content.startIndex
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]
            guard character == "\n" || character == "\r" || character == "\r\n" else {
                index = content.index(after: index)
                continue
            }

            var terminatorEnd = content.index(after: index)
            if character == "\r", terminatorEnd < content.endIndex, content[terminatorEnd] == "\n" {
                terminatorEnd = content.index(after: terminatorEnd)
            }
            lines.append(SourceLine(text: content[lineStart..<index], endIncludingTerminator: terminatorEnd))
            lineStart = terminatorEnd
            index = terminatorEnd
        }

        if lineStart < content.endIndex || lines.isEmpty {
            lines.append(SourceLine(text: content[lineStart...], endIncludingTerminator: content.endIndex))
        }
        return lines
    }

    private static func canonicalKey(for rawKey: String) -> String? {
        let key = rawKey.lowercased()
        switch key {
        case "name", "keyword", "category", "enabled", "show_in_launcher", "show_hud":
            return key
        case "showinlauncher", "launcher":
            return "show_in_launcher"
        default:
            return nil
        }
    }

    private static func decodeScalar(_ value: String, fileURL: URL, line: Int) throws -> String {
        let scalars = value.unicodeScalars
        guard scalars.first == "\"" else {
            throw parseError(fileURL, line: line, "String values must use double quotes")
        }

        var decoded = ""
        var index = scalars.index(after: scalars.startIndex)
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\"" {
                let trailing = scalars[scalars.index(after: index)...]
                guard trailing.allSatisfy({ $0 == " " || $0 == "\t" }) else {
                    throw parseError(fileURL, line: line, "Unexpected text after quoted value")
                }
                return decoded
            }
            if scalar == "\\" {
                let escapeIndex = scalars.index(after: index)
                guard escapeIndex < scalars.endIndex else {
                    throw parseError(fileURL, line: line, "Unterminated escape sequence")
                }
                switch scalars[escapeIndex] {
                case "\\": decoded.append("\\")
                case "\"": decoded.append("\"")
                case "n": decoded.append("\n")
                case "r": decoded.append("\r")
                case "t": decoded.append("\t")
                default:
                    throw parseError(fileURL, line: line, "Unsupported escape sequence")
                }
                index = scalars.index(after: escapeIndex)
                continue
            }
            guard scalar != "\n" && scalar != "\r" && scalar != "\t" else {
                throw parseError(fileURL, line: line, "Control characters must be escaped")
            }
            decoded.unicodeScalars.append(scalar)
            index = scalars.index(after: index)
        }
        throw parseError(fileURL, line: line, "Unterminated quoted value")
    }

    private static func decodeBoolean(_ value: String, fileURL: URL, line: Int) throws -> Bool {
        switch value {
        case "true": return true
        case "false": return false
        default:
            throw parseError(fileURL, line: line, "Boolean values must be exactly 'true' or 'false'")
        }
    }

    private static func encodeScalar(_ value: String) -> String {
        var encoded = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": encoded += "\\\\"
            case "\"": encoded += "\\\""
            case "\n": encoded += "\\n"
            case "\r": encoded += "\\r"
            case "\t": encoded += "\\t"
            default: encoded.unicodeScalars.append(scalar)
            }
        }
        encoded.append("\"")
        return encoded
    }

    private static func defaultName(for fileURL: URL) -> String {
        fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .capitalized(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func parseError(_ fileURL: URL, line: Int, _ reason: String) -> ParseError {
        .invalidFrontmatter(fileURL: fileURL, line: line, reason: reason)
    }
}
