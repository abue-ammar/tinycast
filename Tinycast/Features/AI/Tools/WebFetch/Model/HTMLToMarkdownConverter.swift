import Foundation

public enum HTMLToMarkdownConverter {
    /// Converts raw HTML string into clean, token-efficient Markdown.
    public static func convert(html: String, maxCharacters: Int = 4000) -> String {
        var text = html

        // 1. Remove scripts, styles, noscript, svg, nav, footer, header, aside, iframe, form
        let removePatterns = [
            #"<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>"#,
            #"<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>"#,
            #"<noscript\b[^<]*(?:(?!<\/noscript>)<[^<]*)*<\/noscript>"#,
            #"<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>"#,
            #"<nav\b[^<]*(?:(?!<\/nav>)<[^<]*)*<\/nav>"#,
            #"<footer\b[^<]*(?:(?!<\/footer>)<[^<]*)*<\/footer>"#,
            #"<header\b[^<]*(?:(?!<\/header>)<[^<]*)*<\/header>"#,
            #"<aside\b[^<]*(?:(?!<\/aside>)<[^<]*)*<\/aside>"#,
            #"<iframe\b[^<]*(?:(?!<\/iframe>)<[^<]*)*<\/iframe>"#,
            #"<form\b[^<]*(?:(?!<\/form>)<[^<]*)*<\/form>"#,
            #"<a\s+[^>]*href=["']javascript:[^"']*["'][^>]*>.*?<\/a>"#
        ]

        for pattern in removePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }

        // 2. Extract article or main if present
        if let articleRegex = try? NSRegularExpression(pattern: #"<article\b[^>]*>(.*?)<\/article>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = articleRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            text = String(text[range])
        } else if let mainRegex = try? NSRegularExpression(pattern: #"<main\b[^>]*>(.*?)<\/main>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = mainRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) {
            text = String(text[range])
        }

        // 3. Convert headers
        for level in 1...6 {
            let hPattern = "<h\(level)[^>]*>(.*?)</h\(level)>"
            let prefix = String(repeating: "#", count: level) + " "
            if let regex = try? NSRegularExpression(pattern: hPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n\(prefix)$1\n\n")
            }
        }

        // 4. Convert links: <a href="url">text</a> -> [text](url)
        let linkPattern = #"<a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>"#
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "[$2]($1)")
        }

        // 5. Convert bold and italics
        let boldPattern = #"<(?:strong|b)\b[^>]*>(.*?)<\/(?:strong|b)>"#
        if let regex = try? NSRegularExpression(pattern: boldPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "**$1**")
        }
        let italicPattern = #"<(?:em|i)\b[^>]*>(.*?)<\/(?:em|i)>"#
        if let regex = try? NSRegularExpression(pattern: italicPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "*$1*")
        }

        // 6. Convert code blocks & inline code
        let preCodePattern = #"<pre\b[^>]*><code\b[^>]*>(.*?)<\/code><\/pre>"#
        if let regex = try? NSRegularExpression(pattern: preCodePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n```\n$1\n```\n")
        }
        let inlineCodePattern = #"<code\b[^>]*>(.*?)<\/code>"#
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "`$1`")
        }

        // 7. Convert paragraphs, line breaks, blockquotes, and list items
        let brPattern = #"<br\s*\/?>"#
        if let regex = try? NSRegularExpression(pattern: brPattern, options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        }
        let pPattern = #"<p\b[^>]*>(.*?)<\/p>"#
        if let regex = try? NSRegularExpression(pattern: pPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n$1\n\n")
        }
        let liPattern = #"<li\b[^>]*>(.*?)<\/li>"#
        if let regex = try? NSRegularExpression(pattern: liPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n* $1")
        }
        let bqPattern = #"<blockquote\b[^>]*>(.*?)<\/blockquote>"#
        if let regex = try? NSRegularExpression(pattern: bqPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n> $1\n\n")
        }

        // 8. Strip all remaining HTML tags
        let tagPattern = #"<[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // 9. Decode HTML entities
        text = decodeHTMLEntities(text)

        // 10. Clean noise: empty links, javascript links, social share tags
        let noisePatterns = [
            #"\*?\s*\[\s*\]\([^\)]*\)"#,
            #"\*?\s*\[[^\]]*\]\(javascript:[^\)]*\)"#,
            #"\n\s*\*\s*\n"#
        ]
        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
            }
        }

        // 11. Clean excessive newlines and whitespace
        if let multilineRegex = try? NSRegularExpression(pattern: #"\n{3,}"#) {
            text = multilineRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 12. Bounded character truncation
        if text.count > maxCharacters {
            let index = text.index(text.startIndex, offsetBy: maxCharacters)
            text = String(text[..<index]) + "\n\n[Content truncated...]"
        }

        return text
    }

    public static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8216;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "\"")
            .replacingOccurrences(of: "&#8221;", with: "\"")
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8212;", with: "—")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")

        // Hex and decimal numeric entities
        let entityPattern = #"&#(x?[0-9a-fA-F]+);"#
        if let regex = try? NSRegularExpression(pattern: entityPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let entityRange = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result) {
                    let codeString = String(result[codeRange])
                    let codePoint: UInt32?
                    if codeString.lowercased().hasPrefix("x") {
                        codePoint = UInt32(codeString.dropFirst(), radix: 16)
                    } else {
                        codePoint = UInt32(codeString, radix: 10)
                    }
                    if let codePoint, let scalar = UnicodeScalar(codePoint) {
                        result.replaceSubrange(entityRange, with: String(scalar))
                    }
                }
            }
        }
        return result
    }
}
