import Foundation

/// Host-name lookups for the `dgram` shim: the system resolver answers `.local` through Bonjour.
enum ExtensionNameResolver {
    static func resolve(_ name: RenderValue?) async -> [String] {
        let host = name?.stringValue ?? ""
        guard !host.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) { addresses(of: host) }.value
    }

    /// Blocking, hence the detached task.
    private static func addresses(of host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &head) == 0, let first = head else { return [] }
        defer { freeaddrinfo(first) }

        var found: [String] = []
        var entry: UnsafeMutablePointer<addrinfo>? = first
        while let current = entry {
            var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                current.pointee.ai_addr, current.pointee.ai_addrlen, &text, socklen_t(text.count),
                nil, 0, NI_NUMERICHOST) == 0
            {
                let digits = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                let address = String(decoding: digits, as: UTF8.self)
                if !found.contains(address) { found.append(address) }
            }
            entry = current.pointee.ai_next
        }
        return found
    }
}
