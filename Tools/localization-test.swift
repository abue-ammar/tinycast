import Foundation

struct StringUnit: Decodable {
    let state: String
    let value: String
}

struct Localization: Decodable {
    let stringUnit: StringUnit?
}

struct CatalogEntry: Decodable {
    let comment: String?
    let localizations: [String: Localization]?
    let shouldTranslate: Bool?
}

struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
    let version: String
}

let catalogURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Tinycast/Localizable.xcstrings")
let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

guard catalog.sourceLanguage == "en" else { fail("sourceLanguage must be en") }
guard catalog.version == "1.0" else { fail("unsupported catalog version \(catalog.version)") }
guard catalog.strings.count >= 250 else {
    fail("catalog unexpectedly small (\(catalog.strings.count) entries)")
}

let formatPattern = try NSRegularExpression(
    pattern: #"%(?:\d+\$)?(?:lld|llu|ld|lu|d|u|f|g|@)"#)

func placeholders(in string: String) -> [String] {
    let range = NSRange(string.startIndex..., in: string)
    return formatPattern.matches(in: string, range: range).compactMap { match in
        guard let swiftRange = Range(match.range, in: string) else { return nil }
        return String(string[swiftRange]).replacingOccurrences(
            of: #"%\d+\$"#, with: "%", options: .regularExpression)
    }.sorted()
}

for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
    if entry.shouldTranslate == false { continue }
    guard let chinese = entry.localizations?["zh-Hans"]?.stringUnit else {
        fail("missing zh-Hans translation for \(key)")
    }
    guard chinese.state == "translated", !chinese.value.trimmingCharacters(in: .whitespaces).isEmpty
    else { fail("unfinished zh-Hans translation for \(key)") }
    guard placeholders(in: key) == placeholders(in: chinese.value) else {
        fail("placeholder mismatch for \(key): \(chinese.value)")
    }
}

let required = [
    "Accessibility", "Actions", "Clipboard history is empty", "Copy Answer",
    "Exchange rates unavailable — check your connection.", "No apps found", "Not granted",
    "Paste to %@", "Permissions", "Quit %lld applications?", "Search for apps and commands…",
    "Settings", "This can't be undone.", "Welcome to Tinycast",
]
for key in required where catalog.strings[key] == nil { fail("missing required key \(key)") }

let commentRequired = ["Actions", "Currency", "Default", "Light", "Result", "Size", "Source", "Type"]
for key in commentRequired {
    guard let comment = catalog.strings[key]?.comment, !comment.isEmpty else {
        fail("ambiguous key needs a developer comment: \(key)")
    }
}

let repositoryURL = catalogURL.deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = repositoryURL.appendingPathComponent("Tinycast")
let visibleLiteralPatterns = [
    #"\b(?:Text|Button|Label|Picker|Toggle|SecureField|TextField|SettingsCard|PopoverMenuItem|InfoRow|caption)\s*\(\s*(?:(?:title|label):\s*)?\"((?:\\.|[^\"\\])*)\""#,
    #"\b(?:title|subtitle|header|message):\s*\"((?:\\.|[^\"\\])*)\""#,
    #"\.init\([^\n]*\blabel:\s*\"((?:\\.|[^\"\\])*)\""#,
    #"\.help\s*\(\s*\"((?:\\.|[^\"\\])*)\""#,
    #"String\s*\(\s*localized:\s*\"((?:\\.|[^\"\\])*)\""#,
    #"UnitDef\s*\(\s*\"[^\"]+\"\s*,\s*\"((?:\\.|[^\"\\])*)\""#,
].map { try! NSRegularExpression(pattern: $0) }

let sourceFiles = FileManager.default.enumerator(
    at: sourceURL, includingPropertiesForKeys: nil
)!.compactMap { $0 as? URL }.filter {
    $0.pathExtension == "swift" && !$0.lastPathComponent.hasSuffix(".generated.swift")
}

var missingSourceKeys: [String] = []
var checkedInterpolatedKeys = 0

func decodeFragment(_ raw: String) -> String? {
    try? JSONDecoder().decode(String.self, from: Data("\"\(raw)\"".utf8))
}

func catalogKey(for raw: String) -> String? {
    guard raw.contains(#"\("#) else {
        guard let key = decodeFragment(raw) else { return nil }
        return catalog.strings[key] == nil ? nil : key
    }

    var fragments: [String] = []
    var current = ""
    var index = raw.startIndex
    while index < raw.endIndex {
        let next = raw.index(after: index)
        if raw[index] == "\\", next < raw.endIndex, raw[next] == "(" {
            fragments.append(current)
            current = ""
            var depth = 1
            index = raw.index(after: next)
            while index < raw.endIndex, depth > 0 {
                if raw[index] == "(" { depth += 1 }
                if raw[index] == ")" { depth -= 1 }
                index = raw.index(after: index)
            }
            guard depth == 0 else { return nil }
        } else {
            current.append(raw[index])
            index = next
        }
    }
    fragments.append(current)
    var decoded: [String] = []
    for fragment in fragments {
        guard let value = decodeFragment(fragment) else { return nil }
        decoded.append(value)
    }

    let placeholder = #"%(?:\d+\$)?(?:lld|llu|ld|lu|d|u|f|g|@)"#
    let pattern = "^" + decoded.map(NSRegularExpression.escapedPattern(for:))
        .joined(separator: placeholder) + "$"
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
    let matches = catalog.strings.keys.filter { key in
        expression.firstMatch(
            in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }
    return matches.count == 1 ? matches[0] : nil
}

let interpolationChecks: [(raw: String, key: String)] = [
    (#"Paste to \(name)"#, "Paste to %@"),
    (#"Quit \(count) applications?"#, "Quit %lld applications?"),
    (#"Version \(short) (\(build))"#, "Version %@ (%@)"),
]
for check in interpolationChecks {
    guard catalogKey(for: check.raw) == check.key else {
        fail("could not normalize interpolated source key: \(check.raw)")
    }
}
guard catalogKey(for: #"__missing_localization_probe__ \(value)"#) == nil else {
    fail("missing interpolated catalog keys must be rejected")
}

for file in sourceFiles {
    let source = try String(contentsOf: file, encoding: .utf8)
    let fullRange = NSRange(source.startIndex..., in: source)
    for pattern in visibleLiteralPatterns {
        for match in pattern.matches(in: source, range: fullRange) {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let raw = String(source[range])
            guard !raw.isEmpty else { continue }
            if raw.contains(#"\("#) { checkedInterpolatedKeys += 1 }
            guard catalogKey(for: raw) == nil else { continue }
            let line = source[..<range.lowerBound].reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            }
            let relative = file.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
            missingSourceKeys.append("\(relative):\(line): \(raw)")
        }
    }
}
guard missingSourceKeys.isEmpty else {
    fail("user-visible source keys missing from catalog:\n" + missingSourceKeys.sorted().joined(separator: "\n"))
}

let translatedCount = catalog.strings.values.filter { $0.shouldTranslate != false }.count
print(
    "PASS: \(translatedCount) English keys have complete zh-Hans translations; "
        + "source keys covered (\(checkedInterpolatedKeys) interpolated)")
