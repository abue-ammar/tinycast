import Foundation

private struct Example: Decodable {
    let query: String
    let expected: String
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
        guard examples.allSatisfy({ $0.expected == NaturalCommand.noMatchID || ids.contains($0.expected) })
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
            print("\(answer.model ?? "unknown")\t\(example.query)\t\(example.expected)\t\(answer.choice)\t\(answer.confidence)")
        }

        for threshold in [0.5, 0.6, 0.7, 0.8, 0.9] {
            let accepted = answers.filter {
                $0.1.choice != NaturalCommand.noMatchID && $0.1.confidence >= threshold
            }
            let correct = accepted.filter { $0.0.expected == $0.1.choice }.count
            let missed = answers.filter {
                $0.0.expected != NaturalCommand.noMatchID
                    && ($0.1.choice == NaturalCommand.noMatchID || $0.1.confidence < threshold)
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
