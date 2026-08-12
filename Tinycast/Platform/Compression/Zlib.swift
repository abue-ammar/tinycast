import Compression
import Foundation

enum ZlibError: Error { case notGzip, corrupt, tooLarge }

/// gzip / zlib / raw-DEFLATE, both directions.
///
/// Apple's `Compression` framework only speaks raw DEFLATE (`COMPRESSION_ZLIB` is a misnomer — it
/// omits the zlib wrapper), so the framing and the checksums are done here. That keeps the app free of
/// any zlib linkage or build-system detour, and serves two callers: the Raycast settings import, and
/// the `zlib` Node shim extensions reach for.
enum Zlib {
    /// Real inputs here are a Raycast export (a few KB) or an extension's own payload; the cap stops a
    /// hand-crafted bomb — the import envelope is inflated before it is ever authenticated.
    static let defaultMaxOutput = 64 * 1024 * 1024

    // MARK: - gzip (RFC 1952)

    static func gunzip(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        let bytes = [UInt8](data)
        // Magic (1f 8b) + deflate method (08) + the 10-byte fixed header and 8-byte trailer.
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw ZlibError.notGzip
        }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {  // FEXTRA: 2-byte length + payload
            guard index + 2 <= bytes.count else { throw ZlibError.corrupt }
            index += 2 + (Int(bytes[index]) | Int(bytes[index + 1]) << 8)
        }
        if flags & 0x08 != 0 { index = try skipCString(bytes, from: index) }  // FNAME
        if flags & 0x10 != 0 { index = try skipCString(bytes, from: index) }  // FCOMMENT
        if flags & 0x02 != 0 { index += 2 }  // FHCRC
        guard index < bytes.count - 8 else { throw ZlibError.corrupt }
        // Slice `bytes`, not `data`: `data` may be a slice whose indices start elsewhere.
        return try inflateRaw(Data(bytes[index..<(bytes.count - 8)]), maxOutput: maxOutput)
    }

    static func gzip(_ data: Data) throws -> Data {
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(try deflateRaw(data))
        out.append(littleEndian(crc32(data)))
        out.append(littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    // MARK: - zlib (RFC 1950)

    static func inflate(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        // 0x78 is the only CMF byte deflate produces; anything else is already a raw stream.
        guard data.count > 6, data[data.startIndex] & 0x0f == 8 else {
            return try inflateRaw(data, maxOutput: maxOutput)
        }
        let start = data.startIndex + 2
        let end = data.endIndex - 4
        guard start < end else { throw ZlibError.corrupt }
        return try inflateRaw(data.subdata(in: start..<end), maxOutput: maxOutput)
    }

    static func deflate(_ data: Data) throws -> Data {
        var out = Data([0x78, 0x9c])
        out.append(try deflateRaw(data))
        out.append(bigEndian(adler32(data)))
        return out
    }

    // MARK: - raw DEFLATE (RFC 1951)

    static func inflateRaw(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        try stream(data, operation: COMPRESSION_STREAM_DECODE, maxOutput: maxOutput)
    }

    static func deflateRaw(_ data: Data) throws -> Data {
        try stream(data, operation: COMPRESSION_STREAM_ENCODE, maxOutput: Int.max)
    }

    // MARK: - Internals

    private static func skipCString(_ bytes: [UInt8], from start: Int) throws -> Int {
        var i = start
        while i < bytes.count {
            if bytes[i] == 0 { return i + 1 }
            i += 1
        }
        throw ZlibError.corrupt
    }

    private static func stream(
        _ input: Data, operation: compression_stream_operation, maxOutput: Int
    ) throws -> Data {
        let bufferSize = 256 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        // The C struct has no zero-arg init; placeholder pointers are overwritten before processing.
        var handle = compression_stream(
            dst_ptr: dst, dst_size: bufferSize, src_ptr: dst, src_size: 0, state: nil)
        guard compression_stream_init(&handle, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR
        else { throw ZlibError.corrupt }
        defer { compression_stream_destroy(&handle) }

        enum Outcome { case done(Data), overflow, failed }
        let outcome: Outcome = input.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return .done(Data()) }
            handle.src_ptr = base
            handle.src_size = raw.count
            var out = Data()
            while true {
                handle.dst_ptr = dst
                handle.dst_size = bufferSize
                let status = compression_stream_process(
                    &handle, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    out.append(dst, count: bufferSize - handle.dst_size)
                    if out.count > maxOutput { return .overflow }
                    if status == COMPRESSION_STATUS_END { return .done(out) }
                default:
                    return .failed
                }
            }
        }
        switch outcome {
        case .done(let data): return data
        case .overflow: throw ZlibError.tooLarge
        case .failed: throw ZlibError.corrupt
        }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8(value >> 24)
        ])
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ])
    }
}
