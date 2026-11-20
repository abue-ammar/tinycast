import Foundation

nonisolated enum DictationWire {
    enum Failure: LocalizedError {
        case notInstalled, busy, unavailable
        var errorDescription: String? {
            switch self {
            case .notInstalled: String(localized: "Download the selected dictation model first.")
            case .busy: String(localized: "Wait for the current dictation to finish.")
            case .unavailable: String(localized: "The dictation model couldn't process the recording.")
            }
        }
    }

    static let sampleRate = 16_000
    static let maximumSamples = sampleRate * 60 * 5
    static let maximumMessageBytes = 64_000

    struct Request: Codable, Sendable {
        let id: UUID
        let model: DictationModel
        let directory: URL
        let sampleCount: Int
        let language: String?
    }

    struct Response: Codable, Sendable {
        enum Status: String, Codable { case ready, result, failed }
        let id: UUID
        let status: Status
        var text = ""
    }
}
