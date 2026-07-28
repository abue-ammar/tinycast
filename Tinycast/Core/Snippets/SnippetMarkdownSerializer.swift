import Foundation

struct SnippetMarkdownSerializer {
    static func parse(content: String, fileURL: URL) -> Snippet {
        let lines = content.components(separatedBy: .newlines)
        var name = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
        var keyword: String? = nil
        var category: String? = nil
        var isEnabled: Bool = true
        var showInLauncher: Bool = true

        var bodyLines: [String] = []
        var inFrontmatter = false
        var hasFrontmatter = false
        var frontmatterDone = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if index == 0 && trimmed == "---" {
                inFrontmatter = true
                hasFrontmatter = true
                continue
            }
            if inFrontmatter && trimmed == "---" {
                inFrontmatter = false
                frontmatterDone = true
                continue
            }

            if inFrontmatter {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    var val = parts[1].trimmingCharacters(in: .whitespaces)
                    if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    switch key {
                    case "name":
                        if !val.isEmpty { name = val }
                    case "keyword":
                        keyword = val.isEmpty ? nil : val
                    case "category":
                        category = val.isEmpty ? nil : val
                    case "enabled":
                        isEnabled = val.lowercased() != "false"
                    case "show_in_launcher", "showinlauncher", "launcher":
                        showInLauncher = val.lowercased() != "false"
                    default:
                        break
                    }
                }
            } else if frontmatterDone || !hasFrontmatter {
                bodyLines.append(line)
            }
        }

        var bodyText = bodyLines.joined(separator: "\n")
        while bodyText.hasPrefix("\n") {
            bodyText.removeFirst()
        }

        return Snippet(
            name: name,
            text: bodyText,
            keyword: keyword,
            category: category,
            isEnabled: isEnabled,
            showInLauncher: showInLauncher
        )
    }

    static func serialize(_ snippet: Snippet) -> String {
        var lines = ["---"]
        lines.append("name: \"\(snippet.name)\"")
        if let kw = snippet.keyword, !kw.isEmpty {
            lines.append("keyword: \"\(kw)\"")
        }
        if let cat = snippet.category, !cat.isEmpty {
            lines.append("category: \"\(cat)\"")
        }
        if !snippet.isEnabled {
            lines.append("enabled: false")
        }
        if !snippet.showInLauncher {
            lines.append("show_in_launcher: false")
        }
        lines.append("---")
        lines.append(snippet.text)
        return lines.joined(separator: "\n")
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
}
