import Foundation

/// One JSON message per frame: a four-byte little-endian length, then the payload.
nonisolated enum PipeFraming {
    /// `nil` at a clean end of stream, before any byte of a frame.
    static func read<Value: Decodable>(
        _ type: Value.Type, from handle: FileHandle, maximum: Int
    ) throws -> Value? {
        guard let header = try handle.read(upToCount: 1), !header.isEmpty else { return nil }
        let bytes = header + (try readExactly(3, from: handle))
        let length = bytes.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        guard (1...maximum).contains(length) else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(type, from: readExactly(length, from: handle))
    }

    static func write<Value: Encodable>(_ value: Value, to handle: FileHandle, maximum: Int) throws {
        let frame = try encode(value, maximum: maximum)
        var length = frame.length
        try withUnsafeBytes(of: &length) { try handle.write(contentsOf: $0) }
        try handle.write(contentsOf: frame.payload)
    }

    static func encode<Value: Encodable>(
        _ value: Value, maximum: Int
    ) throws -> (length: UInt32, payload: Data) {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximum else { throw CocoaError(.coderInvalidValue) }
        return (UInt32(data.count).littleEndian, data)
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
