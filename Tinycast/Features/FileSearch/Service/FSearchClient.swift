import Darwin
import Foundation

enum FSearchClient {
    enum Failure: Error {
        case unavailable
        case invalidResponse
    }

    private struct Response: Decodable {
        let ok: Bool
        let hits: [Hit]?
    }

    struct Hit: Decodable, Sendable {
        let path: String
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let responseLimit = 1_048_576

    nonisolated static func search(
        _ request: FSearchRequest, socketPath: String, timeout: Duration = .milliseconds(250)
    ) throws -> [Hit] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let descriptor = try connect(path: socketPath, deadline: deadline)
        defer { close(descriptor) }
        var data = try encoder.encode(request)
        data.append(10)
        try data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                try wait(descriptor, for: POLLOUT, deadline: deadline)
                let count = Darwin.send(
                    descriptor, buffer.baseAddress!.advanced(by: sent), buffer.count - sent, 0)
                if count < 0, errno == EINTR || errno == EAGAIN { continue }
                guard count > 0 else { throw Failure.unavailable }
                sent += count
            }
        }
        let response = try decoder.decode(Response.self, from: receive(descriptor, deadline: deadline))
        guard response.ok, let hits = response.hits, hits.count <= request.limit else {
            throw Failure.invalidResponse
        }
        return hits
    }

    private nonisolated static func connect(
        path: String, deadline: ContinuousClock.Instant
    ) throws -> Int32 {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw Failure.unavailable
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyBytes(from: $0) }
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.unavailable }
        do {
            guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
                fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0
            else { throw Failure.unavailable }
            var enabled: Int32 = 1
            guard
                setsockopt(
                    descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
                    socklen_t(MemoryLayout.size(ofValue: enabled))) == 0
            else { throw Failure.unavailable }
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw Failure.unavailable }
                try wait(descriptor, for: POLLOUT, deadline: deadline)
                var error: Int32 = 0
                var length = socklen_t(MemoryLayout.size(ofValue: error))
                guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0
                else { throw Failure.unavailable }
            }
            var user: uid_t = 0
            var group: gid_t = 0
            guard getpeereid(descriptor, &user, &group) == 0, user == getuid() else {
                throw Failure.unavailable
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private nonisolated static func receive(
        _ descriptor: Int32, deadline: ContinuousClock.Instant
    ) throws -> Data {
        var response = Data()
        response.reserveCapacity(65_536)
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while response.count < responseLimit {
            try wait(descriptor, for: POLLIN, deadline: deadline)
            let count = recv(descriptor, &buffer, min(buffer.count, responseLimit - response.count), 0)
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count > 0 else { throw Failure.invalidResponse }
            if let newline = buffer[..<count].firstIndex(of: 10) {
                response.append(contentsOf: buffer[..<newline])
                return response
            }
            response.append(contentsOf: buffer[..<count])
        }
        throw Failure.invalidResponse
    }

    private nonisolated static func wait(
        _ descriptor: Int32, for event: Int32, deadline: ContinuousClock.Instant
    ) throws {
        while true {
            try Task.checkCancellation()
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw Failure.unavailable }
            let components = remaining.components
            let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
            var descriptor = pollfd(fd: descriptor, events: Int16(event), revents: 0)
            let result = poll(&descriptor, 1, Int32(clamping: max(1, milliseconds)))
            if result < 0, errno == EINTR { continue }
            guard result > 0, descriptor.revents & Int16(event) != 0 else { throw Failure.unavailable }
            return
        }
    }
}
