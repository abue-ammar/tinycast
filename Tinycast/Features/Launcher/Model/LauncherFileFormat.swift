import Foundation

/// A launcher item's row as settings.json spells it: shortcut, alias and launcher visibility.
enum LauncherFileFormat {
    struct Record: Equatable, Sendable {
        var shortcut: String?
        var alias: String?
        var showInLauncher = true

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

    static func records(from json: SettingsFileJSON, current: (String) -> Record) -> Decoded? {
        guard let members = json.members else { return nil }
        var decoded: Decoded = ([:], [])
        for member in members {
            let fields = member.value
            guard fields.members != nil else {
                decoded.records[member.key] = current(member.key)
                decoded.problems.append("“\(member.key)” needs an object")
                continue
            }
            var record = current(member.key)
            text(fields["shortcut"], field: "shortcut", of: member.key, into: &record.shortcut, &decoded)
            text(fields["alias"], field: "alias", of: member.key, into: &record.alias, &decoded)
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
        _ json: SettingsFileJSON?, field: String, of name: String, into value: inout String?,
        _ decoded: inout Decoded
    ) {
        switch json {
        case nil: return
        case .null?: value = nil
        case .string(let text)?: value = text
        default: decoded.problems.append("“\(name)”: “\(field)” needs quotes, or null")
        }
    }
}
