import Foundation

nonisolated enum DictationWire {
    enum Failure: LocalizedError {
        case notInstalled, busy, unavailable
        var errorDescription: String? {
            switch self {
            case .notInstalled: String(localized: "Download the selected dictation model first.")
            case .busy: String(localized: "Wait for the current dictation to finish.")
            case .unavailable: String(localized: "The dictation model couldn't process the recording.")
            }
        }
    }

    static let sampleRate = 16_000
    static let maximumSamples = sampleRate * 60 * 5
    static let maximumMessageBytes = 64_000

    struct Request: Codable, Sendable {
        let id: UUID
        let model: DictationModel
        let directory: URL
        let sampleCount: Int
        let language: String?
    }

    struct Response: Codable, Sendable {
        enum Status: String, Codable { case ready, result, failed }
        let id: UUID
        let status: Status
        var text = ""
    }

    static func read<Value: Decodable>(_ type: Value.Type, from handle: FileHandle) throws -> Value? {
        guard let header = try handle.read(upToCount: 1), !header.isEmpty else { return nil }
        let bytes = header + (try readExactly(3, from: handle))
        let length = bytes.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        guard (1...maximumMessageBytes).contains(length) else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(type, from: readExactly(length, from: handle))
    }

    static func write<Value: Encodable>(_ value: Value, to handle: FileHandle) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumMessageBytes else { throw CocoaError(.coderInvalidValue) }
        var length = UInt32(data.count).littleEndian
        try withUnsafeBytes(of: &length) { try handle.write(contentsOf: $0) }
        try handle.write(contentsOf: data)
    }

    static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let bytes = try handle.read(upToCount: count - data.count), !bytes.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            data.append(bytes)
        }
        return data
    }
}
