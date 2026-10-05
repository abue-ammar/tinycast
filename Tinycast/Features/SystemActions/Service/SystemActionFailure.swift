import Foundation

struct SystemActionFailure: LocalizedError, Sendable {
    enum Settings: Sendable {
        case accessibility
        case automation
        case bluetooth
    }

    let message: String
    let settings: Settings?

    init(_ message: String, settings: Settings? = nil) {
        self.message = message
        self.settings = settings
    }

    var errorDescription: String? { message }
}
