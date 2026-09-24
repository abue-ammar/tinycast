import Foundation

private struct Example: Decodable {
    let query: String
    let expected: String?
    let expectedAny: [String]?

    enum CodingKeys: String, CodingKey {
        case query, expected
        case expectedAny = "expected_any"
    }

    var label: String { expected ?? expectedAny?.joined(separator: ",") ?? "invalid" }

    func accepts(_ suggestions: [String]) -> Bool {
        if expected == NaturalCommand.noMatchID { return suggestions.isEmpty }
        if let expected { return suggestions.first == expected }
        guard let expectedAny, !suggestions.isEmpty else { return false }
        return suggestions.contains { expectedAny.contains($0) }
    }
}

@main
struct NaturalCommandEvaluation {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fputs("Usage: evaluate-natural-commands <corpus> [--baseline|--validate]\n", stderr)
            exit(2)
        }

        let baseline = arguments.contains("--baseline")
        let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        let candidates = makeCandidates(baseline: baseline)
        let ids = Set(candidates.map(\.id))
        guard examples.allSatisfy({ example in
            if let expected = example.expected {
                return example.expectedAny == nil
                    && (expected == NaturalCommand.noMatchID || ids.contains(expected))
            }
            guard let expectedAny = example.expectedAny, !expectedAny.isEmpty else { return false }
            return expectedAny.allSatisfy(ids.contains)
        })
        else {
            fputs("The corpus names a command outside the evaluation candidate set.\n", stderr)
            exit(2)
        }
        if arguments.contains("--validate") {
            print("valid corpus: \(examples.count) cases, \(candidates.count) candidates")
            return
        }

        guard let key = String(
            data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            fputs("Pass a TypeSafe API key on stdin for a live evaluation.\n", stderr)
            exit(2)
        }

        let client = NaturalCommandClient()
        var answers: [(Example, NaturalCommand.ChoiceAnswer)] = []
        print("mode=\(baseline ? "names-only" : "described") candidates=\(candidates.count) cases=\(examples.count)")
        for example in examples {
            let answer = try await client.interpret(query: example.query, candidates: candidates, apiKey: key)
            answers.append((example, answer))
            let suggestions = NaturalCommand.suggestedIDs(answer, candidates: candidates)
            print(
                "\(answer.model ?? "unknown")\t\(example.query)\t\(example.label)\t"
                    + "\(suggestions.joined(separator: ","))\t\(answer.relevance)\t\(answer.confidence)")
        }

        for threshold in [0.5, 0.6, 0.7, 0.8, 0.9] {
            let evaluated = answers.map { example, answer in
                (example, NaturalCommand.suggestedIDs(
                    answer, candidates: candidates, minimumRelevance: threshold))
            }
            let accepted = evaluated.filter { !$0.1.isEmpty }
            let correct = accepted.filter { $0.0.accepts($0.1) }.count
            let missed = evaluated.filter {
                $0.0.expected != NaturalCommand.noMatchID && $0.1.isEmpty
            }.count
            print(
                "threshold=\(threshold) accepted=\(accepted.count) correct=\(correct) "
                + "wrong=\(accepted.count - correct) missed=\(missed)")
        }
    }

    private static func makeCandidates(baseline: Bool) -> [NaturalCommand.Candidate] {
        let windows = WindowCommandCatalog.all.map { command in
            NaturalCommand.Candidate(
                id: command.entryID, name: command.name, kind: "Window Command",
                meaning: baseline ? nil : NaturalCommandWindowMeaning.describe(command.id))
        }
        let system = SystemActionCatalog.all.map { action in
            NaturalCommand.Candidate(id: action.entryID, name: action.name, kind: "System Action")
        }
        let builtIns = [
            NaturalCommand.Candidate(id: "command:clipboard-history", name: "Clipboard History", kind: "Command"),
            NaturalCommand.Candidate(id: "command:show-notes", name: "Show Notes", kind: "Command"),
            NaturalCommand.Candidate(id: "command:search-files", name: "Search Files", kind: "Command"),
            NaturalCommand.Candidate(id: "command:settings", name: "Tinycast Settings", kind: "Command")
        ]
        return windows + system + builtIns
    }
}
