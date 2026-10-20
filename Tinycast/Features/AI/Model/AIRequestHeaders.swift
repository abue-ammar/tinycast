import Foundation

enum AIRequestHeaders {
    struct Entry: Identifiable, Equatable, Sendable {
        let id: UUID
        var name: String
        var value: String

        init(id: UUID = UUID(), name: String = "", value: String = "") {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    enum ValidationError: LocalizedError, Equatable {
        case invalidName
        case duplicateName
        case invalidValue

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return String(localized: "Enter a valid HTTP header name.")
            case .duplicateName:
                return String(localized: "Header names must be unique, ignoring case.")
            case .invalidValue:
                return String(localized: "Header values cannot contain line breaks or control characters.")
            }
        }
    }

    static func validated(_ entries: [Entry]) throws -> [String: String] {
        var result: [String: String] = [:]
        var names: Set<String> = []
        for entry in entries {
            let name = entry.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty, entry.value.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard !name.isEmpty, name.utf8.allSatisfy(isTokenByte) else {
                throw ValidationError.invalidName
            }
            guard names.insert(name.lowercased()).inserted else {
                throw ValidationError.duplicateName
            }
            guard entry.value.unicodeScalars.allSatisfy({
                $0.value == 0x09
                    || (!CharacterSet.controlCharacters.contains($0)
                        && !CharacterSet.newlines.contains($0))
            }) else { throw ValidationError.invalidValue }
            result[name] = entry.value
        }
        return result
    }

    static func apply(_ headers: [String: String], to request: inout URLRequest) throws {
        let entries = headers.map { Entry(name: $0.key, value: $0.value) }
        let headers = try validated(entries)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    static func secrets(_ headers: [String: String]) -> [String] {
        var values: Set<String> = []
        for (name, value) in headers {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            for secret in [value, trimmed] where !secret.isEmpty { values.insert(secret) }
            let name = name.trimmingCharacters(in: .whitespaces).lowercased()
            guard name == "authorization" || name == "proxy-authorization" else { continue }
            let parts = trimmed.split(maxSplits: 1) { $0 == " " || $0 == "\t" }
            guard parts.count == 2 else { continue }
            let token = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if !token.isEmpty { values.insert(token) }
        }
        return values.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
    }

    private static func isTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        default: return "!#$%&'*+-.^_`|~".utf8.contains(byte)
        }
    }
}
