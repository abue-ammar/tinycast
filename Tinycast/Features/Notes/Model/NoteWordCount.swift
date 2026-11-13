import Foundation

enum NoteWordCount {
    @concurrent
    static func count(in source: String) async -> Int {
        let text = source as NSString
        var count = 0
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        return count
    }
}
