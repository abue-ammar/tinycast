import Foundation

/// The bounded TypeSafe vocabulary and its validated interpretation result.
enum NaturalCommand {
    static let model = "jev-1.13.0"
    static let noMatchID = "no_match"
    static let minimumConfidence = 0.70

    struct Candidate: Hashable, Sendable {
        let id: String
        let name: String
        let kind: String
        let meaning: String?

        init(id: String, name: String, kind: String, meaning: String? = nil) {
            self.id = id
            self.name = name
            self.kind = kind
            self.meaning = meaning
        }

        var criterion: String {
            guard let meaning else { return "\(name) — \(kind)" }
            return "\(name) — \(kind). \(meaning)"
        }
    }

    struct ChoiceAnswer: Sendable {
        let model: String?
        let choice: String
        let confidence: Double
        let probabilities: [String: Double]
    }

    enum Resolution: Equatable, Sendable {
        case candidate(String)
        case noMatch
        case uncertain
        case invalid
    }

    struct Run: Sendable {
        enum Phase: Sendable { case requesting, confirming }

        let id: UUID
        let query: String
        let candidates: Set<Candidate>
        private(set) var phase: Phase = .requesting

        mutating func beginConfirmation() { phase = .confirming }

        func shouldCancelPending(
            currentQuery: String, isLauncherVisible: Bool, enabled: Bool, hasKey: Bool
        ) -> Bool {
            phase == .requesting
                && (!isLauncherVisible || currentQuery != query || !enabled || !hasKey)
        }

        func mayPresent(
            currentQuery: String, isLauncherVisible: Bool, enabled: Bool, hasKey: Bool,
            currentCandidates: Set<Candidate>
        ) -> Bool {
            phase == .requesting && !shouldCancelPending(
                currentQuery: currentQuery, isLauncherVisible: isLauncherVisible,
                enabled: enabled, hasKey: hasKey)
                && currentCandidates == candidates
        }

        func mayExecute(enabled: Bool, hasKey: Bool, targetStillAvailable: Bool) -> Bool {
            phase == .confirming && enabled && hasKey && targetStillAvailable
        }
    }

    enum Error: LocalizedError {
        case duplicateCandidateID
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .duplicateCandidateID: return "The command catalog contains duplicate identifiers."
            case .invalidResponse: return "The service returned an invalid command interpretation."
            }
        }
    }

    /// Makes the complete, typed evaluation request. The model can only choose these IDs or no match.
    static func requestData(query: String, candidates: [Candidate]) throws -> Data {
        let ids = candidates.map(\.id)
        guard Set(ids).count == ids.count, !ids.contains(noMatchID) else {
            throw Error.duplicateCandidateID
        }

        var criteria = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.criterion) })
        criteria[noMatchID] = "The request does not clearly map to one available Tinycast command."
        let request = Request(
            state: .init(query: query, availableCommands: candidates), model: model,
            questions: [
                "command": .init(
                    type: "choice",
                    instructions:
                        "Choose the one available Tinycast command that best matches the request. "
                        + "Choose no_match whenever no command is a clear fit.",
                    criteria: criteria)
            ])
        return try JSONEncoder().encode(request)
    }

    static func decodeChoiceAnswer(from data: Data) throws -> ChoiceAnswer {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard
            let answer = response.answers["command"],
            answer.type == "choice",
            answer.confidence.isFinite,
            (0...1).contains(answer.confidence),
            answer.probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
            answer.probabilities[answer.choice] != nil
        else { throw Error.invalidResponse }
        return ChoiceAnswer(
            model: response.model, choice: answer.choice, confidence: answer.confidence,
            probabilities: answer.probabilities)
    }

    /// IDs not in the supplied candidate list are never trusted, whatever the remote response says.
    static func resolve(_ answer: ChoiceAnswer, candidates: [Candidate]) -> Resolution {
        if answer.choice == noMatchID { return .noMatch }
        guard answer.confidence >= minimumConfidence else { return .uncertain }
        guard candidates.contains(where: { $0.id == answer.choice }) else { return .invalid }
        guard answer.probabilities[answer.choice] != nil else { return .invalid }
        return .candidate(answer.choice)
    }
}

private extension NaturalCommand {
    struct Request: Encodable {
        struct State: Encodable {
            let query: String
            let availableCommands: [Candidate]

            enum CodingKeys: String, CodingKey {
                case query
                case availableCommands = "available_commands"
            }
        }

        struct Question: Encodable {
            let type: String
            let instructions: String
            let criteria: [String: String]
        }

        let state: State
        let model: String
        let questions: [String: Question]
    }

    struct Response: Decodable {
        struct Answer: Decodable {
            let type: String
            let choice: String
            let confidence: Double
            let probabilities: [String: Double]
        }

        let model: String?
        let answers: [String: Answer]
    }
}

extension NaturalCommand.Candidate: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case meaning
    }
}
