import Foundation

struct CompactBarSelection: Equatable {
    var command: CommandID?

    mutating func move(by step: Int, commands: [CommandID]) {
        let current = command.flatMap(commands.firstIndex(of:)).map { $0 + 1 } ?? 0
        let next = min(max(current + step, 0), commands.count)
        command = next == 0 ? nil : commands[next - 1]
    }

    mutating func reconcile(commands: [CommandID]) {
        if let command, !commands.contains(command) { self.command = nil }
    }
}
