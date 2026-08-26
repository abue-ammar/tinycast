import Foundation

public final class WebPageReader: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: config)
        }
    }

    public func read(url: URL, maxCharacters: Int = 4000) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.responseFailed("No HTTP response from \(url.host ?? url.absoluteString)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.responseFailed("Failed to fetch webpage (HTTP \(http.statusCode))")
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/pdf") || url.pathExtension.lowercased() == "pdf" {
            if let pdfText = PDFDocumentReader.extractText(from: data, maxCharacters: maxCharacters) {
                return pdfText
            }
        }

        let html = String(decoding: data, as: UTF8.self)
        let markdown = HTMLToMarkdownConverter.convert(html: html, maxCharacters: maxCharacters)
        return markdown.isEmpty ? "The webpage contained no readable text content." : markdown
    }
}
