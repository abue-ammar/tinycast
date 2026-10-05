import Foundation

/// A launcher item's row as settings.json spells it: shortcut, alias and launcher visibility.
enum LauncherFileFormat {
    struct Record: Equatable, Sendable {
        /// Chord text, left for the caller to parse against this Mac's keyboard.
        var shortcut: String?
        var alias: String?
        var showInLauncher = true

        /// What an item the file leaves out has, so only a customized one is written.
        var isEmpty: Bool { shortcut == nil && alias == nil && showInLauncher }
    }

    typealias Decoded = (records: [String: Record], problems: [String])

    static func json(_ records: [(name: String, record: Record)]) -> SettingsFileJSON {
        .object(
            records.map { item in
                SettingsFileJSON.Member(
                    key: item.name,
                    value: .object([
                        "shortcut": text(item.record.shortcut),
                        "alias": text(item.record.alias),
                        "showInLauncher": .bool(item.record.showInLauncher)
                    ]))
            })
    }

    /// A field the record leaves out reads as none, or as shown; a wrong type is reported.
    static func records(from json: SettingsFileJSON) -> Decoded? {
        guard let members = json.members else { return nil }
        var decoded: Decoded = ([:], [])
        for member in members {
            let fields = member.value
            guard fields.members != nil else {
                decoded.problems.append("“\(member.key)” needs an object")
                continue
            }
            var record = Record()
            record.shortcut = text(fields["shortcut"], field: "shortcut", of: member.key, into: &decoded)
            record.alias = text(fields["alias"], field: "alias", of: member.key, into: &decoded)
            switch fields["showInLauncher"] {
            case nil: break
            case .bool(let shown)?: record.showInLauncher = shown
            default: decoded.problems.append("“\(member.key)”: “showInLauncher” needs true or false")
            }
            decoded.records[member.key] = record
        }
        return decoded
    }

    private static func text(_ value: String?) -> SettingsFileJSON {
        value.map(SettingsFileJSON.string) ?? .null
    }

    private static func text(
        _ json: SettingsFileJSON?, field: String, of name: String, into decoded: inout Decoded
    ) -> String? {
        switch json {
        case nil, .null?: return nil
        case .string(let text)?: return text
        default:
            decoded.problems.append("“\(name)”: “\(field)” needs quotes, or null")
            return nil
        }
    }
}
