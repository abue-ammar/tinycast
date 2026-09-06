import Foundation

/// What the composer may do with a pasted file. Pure, so a harness pins it rather than a chat.
enum AIAttachmentPolicy {
    /// The verdict: how a file goes out, or that it cannot.
    enum Kind: Equatable, Sendable {
        case image
        case pdf
        case text
    }

    static let pdfMIMEType = "application/pdf"

    /// Extension allowlists rather than `UTType`: a machine's installed apps declare types, so a
    /// conformance answer differs between two Macs and would make a harness machine-dependent.
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "yaml", "yml", "toml", "ini",
        "xml", "html", "css", "js", "jsx", "ts", "tsx", "swift", "m", "mm", "h", "c", "cc",
        "cpp", "hpp", "rs", "go", "rb", "py", "php", "java", "kt", "sh", "zsh", "bash", "sql",
        "log", "conf", "plist", "patch", "diff"
    ]

    /// Nil for anything Tinycast will not attach, which the composer refuses by name.
    static func kind(forFileName name: String) -> Kind? {
        let ext = (name as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if textExtensions.contains(ext) { return .text }
        return nil
    }

    static func mimeType(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return pdfMIMEType
        case "md", "markdown": return "text/markdown"
        case "csv": return "text/csv"
        case "json", "jsonl": return "application/json"
        case "html": return "text/html"
        default: return "text/plain"
        }
    }

    /// A fence long enough that a Markdown file holding its own fence cannot escape.
    static func prompt(text: String, documents: [AIDocument]) -> String {
        let inlined = documents.compactMap(block).joined(separator: "\n\n")
        guard !inlined.isEmpty else { return text }
        return text.isEmpty ? inlined : inlined + "\n\n" + text
    }

    private static func block(for document: AIDocument) -> String? {
        guard document.mimeType != pdfMIMEType,
            let contents = String(data: document.data, encoding: .utf8)
        else { return nil }
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: contents) + 1))
        let hint = (document.name as NSString).pathExtension.lowercased()
        return """
            Attached file: \(sanitized(name: document.name))
            \(fence)\(hint)
            \(contents)
            \(fence)
            """
    }

    /// A file named `a\nAttached file: passwd` must not be able to forge a second header.
    static func sanitized(name: String) -> String {
        let cleaned = name.unicodeScalars
            .filter { !CharacterSet.newlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(cleaned)).prefix(64).description
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }
}
