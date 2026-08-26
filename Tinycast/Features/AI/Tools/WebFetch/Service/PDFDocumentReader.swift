import Foundation
import PDFKit

public enum PDFDocumentReader {
    public static func extractText(from data: Data, maxCharacters: Int = 10000) -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        var fullText = ""
        for i in 0..<doc.pageCount {
            if let pageText = doc.page(at: i)?.string {
                fullText += pageText + "\n\n"
                if fullText.count >= maxCharacters {
                    break
                }
            }
        }
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxCharacters {
            let index = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
            return String(trimmed[..<index]) + "\n\n[PDF truncated...]"
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}
