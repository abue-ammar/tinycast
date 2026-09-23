import Foundation

enum MCPOAuthChallenge {
    static func parse(_ header: String?) -> [String: String] {
        guard let header, header.utf8.count <= 16_384 else { return [:] }
        var segments: [String] = []
        var segment = ""
        var quoted = false
        var escaped = false
        for character in header {
            if escaped { segment.append(character); escaped = false; continue }
            if character == "\\", quoted { segment.append(character); escaped = true; continue }
            if character == "\"" { quoted.toggle() }
            if character == ",", !quoted {
                segments.append(segment); segment = ""
            } else {
                segment.append(character)
            }
        }
        guard !quoted, !escaped else { return [:] }
        segments.append(segment)
        var bearer = false
        var fields: [String: String] = [:]
        for segment in segments {
            var text = segment.trimmingCharacters(in: .whitespaces)
            if let space = text.firstIndex(where: \.isWhitespace) {
                let prefix = String(text[..<space])
                if !prefix.contains("="), !text[text.index(after: space)...].hasPrefix("=") {
                    if bearer { return fields }
                    bearer = prefix.lowercased() == "bearer"
                    text = String(text[space...]).trimmingCharacters(in: .whitespaces)
                }
            }
            guard bearer, let equal = text.firstIndex(of: "=") else { continue }
            let key = text[..<equal].trimmingCharacters(in: .whitespaces).lowercased()
            var value = text[text.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
                var decoded = ""
                var escape = false
                for character in value {
                    if escape {
                        decoded.append(character)
                        escape = false
                    } else if character == "\\" {
                        escape = true
                    } else {
                        decoded.append(character)
                    }
                }
                value = decoded
            }
            guard fields[key] == nil else { return [:] }
            fields[key] = value
        }
        return fields
    }
}
