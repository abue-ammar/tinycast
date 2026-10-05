import Foundation

/// Metadata extracted from a link's Open Graph and HTML head tags.
struct LinkMetadata: Sendable, Codable, Equatable {
    var title: String?
    var description: String?
    var imageURL: URL?
}

/// Extracts Open Graph, Twitter Card, and HTML head metadata from HTML strings.
enum LinkMetadataParser {
    private static let directImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "bmp", "ico", "tiff"
    ]

    /// Whether the URL points directly at a standalone image rather than a webpage.
    static func isDirectImageURL(_ url: URL) -> Bool {
        directImageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Extracts the preview image URL from an HTML document.
    static func extractOGImageURL(from html: String, baseURL: URL) -> URL? {
        extractMetadata(from: html, baseURL: baseURL).imageURL
    }

    /// Extracts Open Graph and document metadata (title, description, image) from HTML.
    static func extractMetadata(from html: String, baseURL: URL) -> LinkMetadata {
        var ogImage: String?
        var twitterImage: String?
        var linkImage: String?

        var ogTitle: String?
        var twitterTitle: String?
        var htmlTitle: String?
        var metaTitle: String?

        var ogDescription: String?
        var twitterDescription: String?
        var metaDescription: String?

        var index = html.startIndex
        let end = html.endIndex

        while index < end {
            guard let openBracket = html[index...].firstIndex(of: "<") else { break }
            let afterOpen = html.index(after: openBracket)
            guard afterOpen < end else { break }

            // Skip HTML comments so commented-out metadata is ignored.
            if html[afterOpen...].hasPrefix("!--") {
                if let commentEnd = html[afterOpen...].range(of: "-->") {
                    index = commentEnd.upperBound
                    continue
                } else {
                    break
                }
            }

            // Head metadata is all we care about; avoid walking massive document bodies.
            if html[afterOpen...].range(of: "/head>", options: [.caseInsensitive, .anchored]) != nil {
                break
            }

            // Extract <title>...</title> when found.
            if html[afterOpen...].range(of: "title", options: [.caseInsensitive, .anchored]) != nil {
                if let titleTagClose = html[afterOpen...].firstIndex(of: ">") {
                    let titleBodyStart = html.index(after: titleTagClose)
                    if let titleEndTag = html[titleBodyStart...].range(of: "</title>", options: .caseInsensitive) {
                        let raw = String(html[titleBodyStart..<titleEndTag.lowerBound])
                        let normalized = normalizeText(decodeHTMLEntities(raw))
                        if !normalized.isEmpty, htmlTitle == nil {
                            htmlTitle = normalized
                        }
                        index = titleEndTag.upperBound
                        continue
                    }
                }
            }

            guard let closeBracket = html[afterOpen...].firstIndex(of: ">") else { break }
            let tagContent = html[afterOpen..<closeBracket]
            index = html.index(after: closeBracket)

            if tagContent.range(of: "meta", options: [.caseInsensitive, .anchored]) != nil {
                let attrs = parseAttributes(tagContent.dropFirst(4))
                let key = (attrs["property"] ?? attrs["name"])?.lowercased()
                if let rawContent = attrs["content"], !rawContent.isEmpty {
                    let content = decodeHTMLEntities(rawContent.trimmingCharacters(in: .whitespacesAndNewlines))
                    switch key {
                    case "og:image", "og:image:url", "og:image:secure_url":
                        if ogImage == nil { ogImage = content }
                    case "twitter:image", "twitter:image:src":
                        if twitterImage == nil { twitterImage = content }
                    case "og:title":
                        if ogTitle == nil { ogTitle = normalizeText(content) }
                    case "twitter:title":
                        if twitterTitle == nil { twitterTitle = normalizeText(content) }
                    case "title":
                        if metaTitle == nil { metaTitle = normalizeText(content) }
                    case "og:description":
                        if ogDescription == nil { ogDescription = normalizeText(content) }
                    case "twitter:description":
                        if twitterDescription == nil { twitterDescription = normalizeText(content) }
                    case "description":
                        if metaDescription == nil { metaDescription = normalizeText(content) }
                    default:
                        break
                    }
                }
            } else if tagContent.range(of: "link", options: [.caseInsensitive, .anchored]) != nil {
                let attrs = parseAttributes(tagContent.dropFirst(4))
                if attrs["rel"]?.lowercased() == "image_src", let href = attrs["href"], !href.isEmpty {
                    if linkImage == nil { linkImage = href }
                }
            }
        }

        let finalTitle = ogTitle ?? twitterTitle ?? htmlTitle ?? metaTitle
        let finalDescription = ogDescription ?? twitterDescription ?? metaDescription
        let imageCandidate = ogImage ?? twitterImage ?? linkImage
        let finalImageURL = imageCandidate.flatMap { resolve($0, against: baseURL) }

        return LinkMetadata(title: finalTitle, description: finalDescription, imageURL: finalImageURL)
    }

    private static func parseAttributes(_ substring: Substring) -> [String: String] {
        var attrs: [String: String] = [:]
        var index = substring.startIndex
        let end = substring.endIndex

        while index < end {
            while index < end && (substring[index].isWhitespace || substring[index] == "/") {
                index = substring.index(after: index)
            }
            guard index < end else { break }

            let keyStart = index
            while index < end && !substring[index].isWhitespace && substring[index] != "=" && substring[index] != "/" && substring[index] != ">" {
                index = substring.index(after: index)
            }
            let key = String(substring[keyStart..<index]).lowercased()
            guard !key.isEmpty else { break }

            while index < end && substring[index].isWhitespace {
                index = substring.index(after: index)
            }

            if index < end && substring[index] == "=" {
                index = substring.index(after: index)
                while index < end && substring[index].isWhitespace {
                    index = substring.index(after: index)
                }
                guard index < end else {
                    attrs[key] = ""
                    break
                }

                let quote = substring[index]
                if quote == "\"" || quote == "'" {
                    index = substring.index(after: index)
                    let valStart = index
                    while index < end && substring[index] != quote {
                        index = substring.index(after: index)
                    }
                    attrs[key] = String(substring[valStart..<index])
                    if index < end {
                        index = substring.index(after: index)
                    }
                } else {
                    let valStart = index
                    while index < end && !substring[index].isWhitespace && substring[index] != "/" && substring[index] != ">" {
                        index = substring.index(after: index)
                    }
                    attrs[key] = String(substring[valStart..<index])
                }
            } else {
                attrs[key] = ""
            }
        }
        return attrs
    }

    private static func resolve(_ rawString: String, against baseURL: URL) -> URL? {
        let decoded = decodeHTMLEntities(rawString.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !decoded.isEmpty else { return nil }
        if decoded.hasPrefix("//") {
            let scheme = baseURL.scheme ?? "https"
            return URL(string: "\(scheme):\(decoded)")
        }
        let url = URL(string: decoded, relativeTo: baseURL)
            ?? URL(string: decoded.replacingOccurrences(of: " ", with: "%20"), relativeTo: baseURL)
        guard let resolved = url?.absoluteURL else { return nil }
        guard resolved.scheme == "http" || resolved.scheme == "https" else { return nil }
        return resolved
    }

    private static func normalizeText(_ string: String) -> String {
        string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = string
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        return result
    }
}
