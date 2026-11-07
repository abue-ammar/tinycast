import CoreServices
import Darwin
import Foundation

/// Looks a term up in the dictionaries enabled in Dictionary.app, entirely on this Mac.
enum DictionaryService {
    /// Blocking and parse-heavy for a long entry, so the session runs it off the main actor.
    nonisolated static func entry(for term: String, in scope: DictionaryScope) -> DictionaryEntry? {
        if let blocks = DictionaryRecords.resolved?.blocks(for: term, in: scope) {
            return DictionaryEntry(term: term, blocks: blocks)
        }
        // The public call reads every enabled dictionary, so it cannot answer for the thesauri alone.
        guard scope == .dictionary else { return nil }
        return plainText(for: term).map { DictionaryEntry(term: term, plainText: $0) }
    }

    nonisolated static func hasThesaurus() -> Bool {
        DictionaryRecords.resolved?.hasThesaurus() ?? false
    }

    private nonisolated static func plainText(for term: String) -> String? {
        let range = CFRange(location: 0, length: term.utf16.count)
        guard let text = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue()
        else { return nil }
        let trimmed = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Dictionary Services' record calls: what Dictionary.app reads, though no header declares them.
private struct DictionaryRecords: Sendable {
    private typealias ActiveDictionaries = @convention(c) () -> Unmanaged<CFArray>?
    private typealias CopyRecords =
        @convention(c) (
            DCSDictionary, CFString, UnsafeRawPointer?, UnsafeRawPointer?
        ) -> Unmanaged<CFArray>?
    private typealias CopyData = @convention(c) (CFTypeRef, CFIndex) -> Unmanaged<CFString>?
    private typealias GetURL = @convention(c) (DCSDictionary) -> Unmanaged<CFURL>?

    /// `DCSRecordCopyData`'s XHTML version; the plain-text one is what the public API returns.
    private static let xhtml: CFIndex = 0

    private let activeDictionaries: ActiveDictionaries
    private let copyRecords: CopyRecords
    private let copyData: CopyData
    private let url: GetURL

    /// Looked up at run time: a macOS that drops a symbol loses the layout, not the launch.
    static let resolved: DictionaryRecords? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let active = dlsym(rtldDefault, "DCSGetActiveDictionaries"),
            let records = dlsym(rtldDefault, "DCSCopyRecordsForSearchString"),
            let data = dlsym(rtldDefault, "DCSRecordCopyData"),
            let url = dlsym(rtldDefault, "DCSDictionaryGetURL")
        else { return nil }
        return DictionaryRecords(
            activeDictionaries: unsafeBitCast(active, to: ActiveDictionaries.self),
            copyRecords: unsafeBitCast(records, to: CopyRecords.self),
            copyData: unsafeBitCast(data, to: CopyData.self),
            url: unsafeBitCast(url, to: GetURL.self))
    }()

    func hasThesaurus() -> Bool {
        dictionaries().contains(where: isThesaurus)
    }

    /// The first enabled dictionary in scope that knows the term, in Dictionary.app's own order.
    func blocks(for term: String, in scope: DictionaryScope) -> [DictionaryEntry.Block]? {
        for dictionary in dictionaries() {
            if scope == .thesaurus, !isThesaurus(dictionary) { continue }
            guard
                let records = copyRecords(dictionary, term as CFString, nil, nil)?
                    .takeRetainedValue() as? [CFTypeRef]
            else { continue }
            let blocks = records.flatMap { record in
                (copyData(record, Self.xhtml)?.takeRetainedValue() as String?)
                    .map(DictionaryMarkup.blocks(fromXHTML:)) ?? []
            }
            if !blocks.isEmpty { return blocks }
        }
        return nil
    }

    private func dictionaries() -> [DCSDictionary] {
        activeDictionaries()?.takeUnretainedValue() as? [DCSDictionary] ?? []
    }

    /// No key marks a thesaurus, but every one Apple ships names itself so in `CFBundleName`.
    private func isThesaurus(_ dictionary: DCSDictionary) -> Bool {
        guard let location = url(dictionary)?.takeUnretainedValue() as URL?,
            let name = Bundle(url: location)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        else { return false }
        return name.contains("Thesaurus")
    }
}
