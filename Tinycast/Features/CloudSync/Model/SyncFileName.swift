import Foundation

/// A Markdown file name another Mac sent, checked before it can name a file here.
enum SyncFileName {
    static func isValid(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".md") && name.count > 3 && name.utf8.count < 255
            && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\0")
    }
}
