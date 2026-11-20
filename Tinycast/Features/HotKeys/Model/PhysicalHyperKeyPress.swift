import Foundation

/// The two input callbacks can deliver the same hardware release in either order.
struct ForwardedQuickPress: Sendable {
    enum Source { case keyboard, quartz }

    private struct Release: Sendable {
        let source: Source
        let timestamp: UInt64
        let duration: TimeInterval
    }
    private var pending: [Release] = []

    mutating func confirm(_ source: Source, timestamp: UInt64, duration: TimeInterval) -> TimeInterval? {
        guard timestamp != 0 else { return nil }
        if let index = pending.firstIndex(where: { $0.timestamp == timestamp }) {
            guard pending[index].source != source else { return nil }
            let other = pending.remove(at: index)
            return source == .keyboard ? duration : other.duration
        }
        // A device taken over by another app may never produce the matching Quartz release.
        if pending.count == 32 { pending.removeFirst() }
        pending.append(Release(source: source, timestamp: timestamp, duration: duration))
        return nil
    }
}

struct PhysicalHyperKeyPress {
    let mapping: HIDKeyMapping
    private struct Hold {
        let device: UInt32
        let usage: UInt64
        var unusedSince: TimeInterval?
    }
    private var hold: Hold?

    init(mapping: HIDKeyMapping) {
        self.mapping = mapping
    }

    mutating func remove(device: UInt32) {
        if hold?.device == device { hold = nil }
    }

    mutating func handle(device: UInt32, usage: UInt64, down: Bool, at time: TimeInterval) -> TimeInterval? {
        if let current = hold, current.device == device, current.usage == usage {
            guard !down else { return nil }
            hold = nil
            return current.unusedSince.map { time - $0 }
        }
        if hold != nil {
            if down || (0x7_0000_00E0...0x7_0000_00E7).contains(usage) || Self.fnUsages.contains(usage) {
                hold?.unusedSince = nil
            }
        } else if down && (usage == mapping.source || usage == mapping.destination) {
            hold = Hold(device: device, usage: usage, unusedSince: time)
        }
        return nil
    }

    static let fnUsages: [UInt64] = [0x00FF_0000_0003, 0xFF01_0000_0003]
}
