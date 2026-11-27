import Compression
import Foundation

enum ZlibError: Error { case notGzip, corrupt, tooLarge }

/// Apple's `Compression` speaks only raw DEFLATE, so the gzip framing is read here.
enum Zlib {
    /// The cap stops a bomb: the import envelope is inflated before it is authenticated.
    static let defaultMaxOutput = 64 * 1024 * 1024

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

    private static func skipCString(_ bytes: [UInt8], from start: Int) throws -> Int {
        var i = start
        while i < bytes.count {
            if bytes[i] == 0 { return i + 1 }
            i += 1
        }
        throw ZlibError.corrupt
    }

    private static func inflateRaw(_ input: Data, maxOutput: Int) throws -> Data {
        let bufferSize = 256 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        // The C struct has no zero-arg init; the placeholders are overwritten before use.
        var handle = compression_stream(
            dst_ptr: dst, dst_size: bufferSize, src_ptr: dst, src_size: 0, state: nil)
        guard
            compression_stream_init(&handle, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                != COMPRESSION_STATUS_ERROR
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
}
