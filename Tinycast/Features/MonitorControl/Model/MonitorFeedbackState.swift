import Foundation

struct MonitorFeedbackState {
    private(set) var latest: MonitorKeyRouting.Command?
    private(set) var pending = false

    mutating func begin(_ command: MonitorKeyRouting.Command) {
        latest = command
        pending = true
    }

    mutating func finish(_ command: MonitorKeyRouting.Command, failed: Bool) -> Bool {
        guard let latest, latest.generation == command.generation,
            latest.displayID == command.displayID, latest.control == command.control,
            failed || latest.revision == command.revision else { return false }
        pending = false
        return true
    }
}
