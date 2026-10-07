import Foundation

struct ClipboardSourceHistory {
    static let capacity = 64
    private(set) var writers: [Int: Int32] = [:]

    mutating func record(_ message: String, pasteboardName: String) {
        let prefix = "\(pasteboardName) has new generation "
        guard message.hasPrefix(prefix),
            let match = message.firstMatch(of: /has new generation (\d+).*? - pid: (\d+) -/),
            let generation = Int(match.1), let pid = Int32(match.2), pid > 0
        else { return }
        writers[generation] = pid
        if writers.count > Self.capacity, let oldest = writers.keys.min() {
            writers.removeValue(forKey: oldest)
        }
    }

    mutating func reset() {
        writers.removeAll(keepingCapacity: true)
    }
}
