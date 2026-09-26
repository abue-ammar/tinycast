import Foundation

struct MonitorCommandQueue: Sendable {
    private(set) var generation: UInt64 = 0
    private var pending: [MonitorKeyRouting.Command] = []

    mutating func reset(generation: UInt64) {
        self.generation = generation
        pending.removeAll()
    }

    mutating func enqueue(_ command: MonitorKeyRouting.Command) {
        guard command.generation == generation else { return }
        if let index = pending.firstIndex(where: {
            $0.displayID == command.displayID && $0.control == command.control
        }) {
            var latest = command
            latest.adjustment = pending[index].adjustment.followed(by: command.adjustment)
            pending[index] = latest
        } else {
            pending.append(command)
        }
    }

    mutating func next() -> MonitorKeyRouting.Command? {
        pending.isEmpty ? nil : pending.removeFirst()
    }
}
