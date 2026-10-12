import Darwin
import Foundation

/// Every live process under this one, by executable path. A process gone mid-walk is skipped.
enum DescendantProcessScanner {
    static func executablePaths(under root: pid_t = getpid()) -> [String] {
        var paths: [String] = []
        var pending = [root]
        while let parent = pending.popLast() {
            for child in children(of: parent) {
                pending.append(child)
                if let path = executablePath(of: child) { paths.append(path) }
            }
        }
        return paths
    }

    /// Sized from the kernel's estimate plus slack, since a child can start between the two calls.
    private static func children(of parent: pid_t) -> [pid_t] {
        let estimate = proc_listchildpids(parent, nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 8)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listchildpids(parent, buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}
