import Foundation

struct MonitorCommandQueue: Sendable {
    private(set) var generation: UInt64 = 0
    private var pending: [MonitorKeyRouting.Command] = []
    var isEmpty: Bool { pending.isEmpty }

    mutating func reset(generation: UInt64) {
        self.generation = generation
        pending.removeAll()
    }

    mutating func enqueue(_ command: MonitorKeyRouting.Command) {
        guard command.generation == generation else { return }
        if let index = pending.indices.last, pending[index].displayID == command.displayID,
            pending[index].control == command.control, pending[index].audioGeneration == command.audioGeneration {
            var latest = command
            latest.adjustment = pending[index].adjustment.followed(by: command.adjustment)
            pending[index] = latest
        } else {
            pending.append(command)
        }
    }

    mutating func cancelAudio() {
        pending.removeAll { $0.control != .brightness }
    }

    mutating func next() -> MonitorKeyRouting.Command? {
        pending.isEmpty ? nil : pending.removeFirst()
    }
}
