import Foundation

/// The bounded TypeSafe vocabulary and its validated interpretation result.
enum NaturalCommand {
    static let model = "jev-1.13.0"
    static let noMatchID = "no_match"
    static let minimumRelevance = 0.70
    static let maximumSuggestions = 6

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
        let relevance: Double
    }

    struct Run: Sendable {
        enum Phase: Equatable, Sendable { case requesting, choosing, confirming }

        let id: UUID
        let query: String
        let candidates: Set<Candidate>
        private(set) var phase: Phase = .requesting

        mutating func beginChoosing() { phase = .choosing }
        mutating func beginConfirmation() { phase = .confirming }
        mutating func resumeChoosing() { phase = .choosing }

        func shouldClearForContext(
            currentQuery: String, isLauncherVisible: Bool, enabled: Bool, hasKey: Bool
        ) -> Bool {
            phase != .confirming
                && (!isLauncherVisible || currentQuery != query || !enabled || !hasKey)
        }

        func mayPresent(
            currentQuery: String, isLauncherVisible: Bool, enabled: Bool, hasKey: Bool,
            currentCandidates: Set<Candidate>
        ) -> Bool {
            phase == .requesting && !shouldClearForContext(
                currentQuery: currentQuery, isLauncherVisible: isLauncherVisible,
                enabled: enabled, hasKey: hasKey)
                && currentCandidates == candidates
        }

        func mayChoose(
            currentQuery: String, isLauncherVisible: Bool, enabled: Bool, hasKey: Bool,
            currentCandidates: Set<Candidate>
        ) -> Bool {
            phase == .choosing && !shouldClearForContext(
                currentQuery: currentQuery, isLauncherVisible: isLauncherVisible,
                enabled: enabled, hasKey: hasKey)
                && currentCandidates == candidates
        }

        func mayExecute(
            currentQuery: String, enabled: Bool, hasKey: Bool, targetStillAvailable: Bool
        ) -> Bool {
            phase == .confirming && currentQuery == query && enabled && hasKey && targetStillAvailable
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

    static func shouldInterpret(
        query: String, hasLocalAnswer: Bool, enabled: Bool, hasKey: Bool
    ) -> Bool {
        !hasLocalAnswer && enabled && hasKey
            && query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    /// Makes the complete, typed evaluation request over the available command IDs.
    static func requestData(query: String, candidates: [Candidate]) throws -> Data {
        let ids = candidates.map(\.id)
        guard Set(ids).count == ids.count, !ids.contains(noMatchID) else {
            throw Error.duplicateCandidateID
        }

        let criteria = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.criterion) })
        let request = Request(
            state: .init(query: query, availableCommands: candidates), model: model,
            questions: [
                "command": .init(
                    type: "choice",
                    instructions:
                        "Rank available Tinycast commands as search results for the query. "
                        + "If several commands fit a broad query, consider each relevant.",
                    criteria: criteria),
                "related": .init(
                    type: "noul",
                    instructions:
                        "Does the query refer to at least one command in `available_commands`? "
                        + "A broad request can match several commands without naming one exactly.",
                    criteria: [
                        "true": "At least one available command is relevant to the query.",
                        "false": "No available command is relevant to the query."
                    ])
            ])
        return try JSONEncoder().encode(request)
    }

    static func decodeChoiceAnswer(from data: Data) throws -> ChoiceAnswer {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard
            let answer = response.answers["command"],
            let related = response.answers["related"],
            answer.type == "choice",
            related.type == "noul",
            let choice = answer.choice,
            let confidence = answer.confidence,
            let probabilities = answer.probabilities,
            let relevance = related.noul,
            relevance.isFinite,
            (0...1).contains(relevance),
            confidence.isFinite,
            (0...1).contains(confidence),
            probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
            probabilities[choice] != nil
        else { throw Error.invalidResponse }
        return ChoiceAnswer(
            model: response.model, choice: choice, confidence: confidence,
            probabilities: probabilities, relevance: relevance)
    }

    /// The existence judgment gates search results; Choice confidence may be low for a broad query.
    static func suggestedIDs(
        _ answer: ChoiceAnswer, candidates: [Candidate], limit: Int = maximumSuggestions,
        minimumRelevance: Double = NaturalCommand.minimumRelevance
    ) -> [String] {
        let available = Set(candidates.map(\.id))
        guard
            limit > 0, answer.relevance >= minimumRelevance,
            available.contains(answer.choice),
            Set(answer.probabilities.keys).isSubset(of: available),
            let leadingProbability = answer.probabilities[answer.choice], leadingProbability > 0
        else {
            return []
        }
        let floor = leadingProbability * 0.25
        return answer.probabilities
            .filter { available.contains($0.key) && $0.value >= floor }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
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
            let choice: String?
            let confidence: Double?
            let probabilities: [String: Double]?
            let noul: Double?
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
