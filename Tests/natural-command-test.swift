import Foundation

@main
@MainActor
struct NaturalCommandTests {
    static var failures = 0
    static var passes = 0

    static let candidates = [
        NaturalCommand.Candidate(
            id: "window-command:last-third", name: "Last Third", kind: "Window Command",
            meaning: NaturalCommandWindowMeaning.describe(.lastThird)),
        NaturalCommand.Candidate(
            id: "system-action:lock-screen", name: "Lock Screen", kind: "System Action")
    ]

    static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(description)")
        }
    }

    static func main() {
        requestContainsOnlyTheBoundedVocabulary()
        validChoiceOffersTheCandidate()
        unrelatedQueryOffersNoCommand()
        unknownChoiceOffersNoCommand()
        malformedResponseIsRejected()
        duplicateCandidateIDsAreRejected()
        automaticFallbackRequiresAnEmptyLocalSearch()
        responseOffersRankedChoicesWithoutRunningOne()
        requestContextRejectsStaleResults()
        windowMeaningsDistinguishSimilarCommands()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func requestContainsOnlyTheBoundedVocabulary() {
        do {
            let data = try NaturalCommand.requestData(
                query: "Move Window to Right Third", candidates: candidates)
            let request = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let state = request?["state"] as? [String: Any]
            let question = (request?["questions"] as? [String: Any])?["command"] as? [String: Any]
            let related = (request?["questions"] as? [String: Any])?["related"] as? [String: Any]
            let criteria = question?["criteria"] as? [String: String]

            check("request pins the TypeSafe model", request?["model"] as? String == "jev-1.13.0")
            check("request carries the typed query", state?["query"] as? String == "Move Window to Right Third")
            check(
                "request carries only supplied command IDs",
                Set(criteria.map { Array($0.keys) } ?? []) == Set(candidates.map(\.id)))
            check(
                "request describes each candidate",
                criteria?[candidates[0].id]?.contains("rightmost third") == true)
            let available = state?["available_commands"] as? [[String: String]]
            check("state carries the same fixed meaning", available?.first?["meaning"] == candidates[0].meaning)
            check("Choice has no competing no-match option", criteria?[NaturalCommand.noMatchID] == nil)
            check("request checks if any candidate is related", related?["type"] as? String == "noul")
        } catch {
            check("request encodes", false)
        }
    }

    static func validChoiceOffersTheCandidate() {
        let answer = decode(
            choice: candidates[0].id, confidence: 0.91,
            probabilities: [candidates[0].id: 0.91, candidates[1].id: 0.09])
        check(
            "a relevant approved choice is offered",
            NaturalCommand.suggestedIDs(answer, candidates: candidates) == [candidates[0].id])
        check(
            "omitted zero-probability candidates do not hide a valid choice",
            NaturalCommand.suggestedIDs(
                decode(choice: candidates[0].id, confidence: 1,
                       probabilities: [candidates[0].id: 1]),
                candidates: candidates) == [candidates[0].id])
    }

    static func unrelatedQueryOffersNoCommand() {
        let answer = decode(
            choice: candidates[0].id, confidence: 0.95,
            probabilities: [candidates[0].id: 0.95, candidates[1].id: 0.05], relevance: 0.12)
        check(
            "an unrelated query offers no command",
            NaturalCommand.suggestedIDs(answer, candidates: candidates).isEmpty)
    }

    static func unknownChoiceOffersNoCommand() {
        let answer = decode(
            choice: "system-action:shut-down", confidence: 0.99,
            probabilities: ["system-action:shut-down": 0.99, candidates[0].id: 0.01])
        check(
            "an unapproved response ID offers no command",
            NaturalCommand.suggestedIDs(answer, candidates: candidates).isEmpty)
    }

    static func malformedResponseIsRejected() {
        let data = Data("{\"answers\":{\"command\":{\"type\":\"noul\"}}}".utf8)
        do {
            _ = try NaturalCommand.decodeChoiceAnswer(from: data)
            check("a malformed response is rejected", false)
        } catch {
            check("a malformed response is rejected", true)
        }
        let missingRelevance = Data(
            """
            {"answers":{"command":{"type":"choice","choice":"x","confidence":1,
            "probabilities":{"x":1}}}}
            """.utf8)
        do {
            _ = try NaturalCommand.decodeChoiceAnswer(from: missingRelevance)
            check("a response without a relevance answer is rejected", false)
        } catch {
            check("a response without a relevance answer is rejected", true)
        }
    }

    static func duplicateCandidateIDsAreRejected() {
        do {
            _ = try NaturalCommand.requestData(
                query: "lock", candidates: [candidates[0], candidates[0]])
            check("duplicate candidate IDs are rejected", false)
        } catch {
            check("duplicate candidate IDs are rejected", true)
        }
    }

    static func automaticFallbackRequiresAnEmptyLocalSearch() {
        check("an unmatched query can use TypeSafe", NaturalCommand.shouldInterpret(
            query: "move window right", hasLocalAnswer: false, enabled: true, hasKey: true))
        check("a fuzzy match prevents TypeSafe", !NaturalCommand.shouldInterpret(
            query: "move window right", hasLocalAnswer: true, enabled: true, hasKey: true))
        check("a short query stays local", !NaturalCommand.shouldInterpret(
            query: "go", hasLocalAnswer: false, enabled: true, hasKey: true))
        check("the feature switch prevents TypeSafe", !NaturalCommand.shouldInterpret(
            query: "move window right", hasLocalAnswer: false, enabled: false, hasKey: true))
        check("a missing key prevents TypeSafe", !NaturalCommand.shouldInterpret(
            query: "move window right", hasLocalAnswer: false, enabled: true, hasKey: false))
    }

    static func responseOffersRankedChoicesWithoutRunningOne() {
        let answer = decode(
            choice: candidates[0].id, confidence: 0.88,
            probabilities: [candidates[0].id: 0.75, candidates[1].id: 0.25])
        check(
            "a response can offer the chosen command and an alternative",
            NaturalCommand.suggestedIDs(answer, candidates: candidates)
                == candidates.map(\.id))
        let moving = WindowCommandCatalog.all.filter { $0.group == .moving }.map { command in
            NaturalCommand.Candidate(
                id: command.entryID, name: command.name, kind: "Window Command",
                meaning: NaturalCommandWindowMeaning.describe(command.id))
        }
        var broadProbabilities = Dictionary(uniqueKeysWithValues: moving.map { ($0.id, 0.15) })
        broadProbabilities[moving[0].id] = 0.25
        check(
            "a broad request can show all six related Move choices",
            Set(NaturalCommand.suggestedIDs(
                decode(choice: moving[0].id, confidence: 0.14,
                       probabilities: broadProbabilities), candidates: moving))
                == Set(moving.map(\.id)))
        let windows = WindowCommandCatalog.all.map { command in
            NaturalCommand.Candidate(id: command.entryID, name: command.name, kind: "Window Command")
        }
        let diffuse = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, 1.0 / Double(windows.count)) })
        check(
            "a broad request still offers choices from a large command family",
            NaturalCommand.suggestedIDs(
                decode(choice: windows[0].id, confidence: 0.01,
                       probabilities: diffuse), candidates: windows).count == 6)
    }

    static func requestContextRejectsStaleResults() {
        var run = NaturalCommand.Run(
            id: UUID(), query: "move window right", candidates: Set(candidates))
        let current = Set(candidates)
        check(
            "an unchanged search may present a result",
            run.mayPresent(
                currentQuery: run.query, isLauncherVisible: true, enabled: true, hasKey: true,
                currentCandidates: current))
        check(
            "editing the query cancels the pending request",
            run.shouldClearForContext(
                currentQuery: "move window left", isLauncherVisible: true,
                enabled: true, hasKey: true))
        check(
            "closing the launcher cancels the pending request",
            run.shouldClearForContext(
                currentQuery: run.query, isLauncherVisible: false,
                enabled: true, hasKey: true))
        check(
            "a changed command catalog cannot present its old answer",
            !run.mayPresent(
                currentQuery: run.query, isLauncherVisible: true, enabled: true, hasKey: true,
                currentCandidates: [candidates[0]]))
        run.beginChoosing()
        check(
            "a stable result may be chosen",
            run.mayChoose(
                currentQuery: run.query, isLauncherVisible: true, enabled: true, hasKey: true,
                currentCandidates: current))
        check(
            "publishing choices does not authorize execution",
            !run.mayExecute(
                currentQuery: run.query, enabled: true, hasKey: true,
                targetStillAvailable: true))
        check(
            "a changed catalog removes the visible choices",
            !run.mayChoose(
                currentQuery: run.query, isLauncherVisible: true, enabled: true, hasKey: true,
                currentCandidates: [candidates[0]]))
        check(
            "a visible choice is cleared when its search changes",
            run.shouldClearForContext(
                currentQuery: "move window left", isLauncherVisible: true,
                enabled: true, hasKey: true))
        check(
            "a visible choice is cleared when the launcher closes",
            run.shouldClearForContext(
                currentQuery: run.query, isLauncherVisible: false,
                enabled: true, hasKey: true))
        run.beginConfirmation()
        check(
            "a dialog can finish after the palette loses focus",
            !run.shouldClearForContext(
                currentQuery: run.query, isLauncherVisible: false, enabled: true, hasKey: true))
        check("an available confirmed command may run", run.mayExecute(
            currentQuery: run.query, enabled: true, hasKey: true, targetStillAvailable: true))
        check("a changed query prevents confirmed execution", !run.mayExecute(
            currentQuery: "move window left", enabled: true, hasKey: true,
            targetStillAvailable: true))
        check("disabling the feature prevents the confirmed command", !run.mayExecute(
            currentQuery: run.query, enabled: false, hasKey: true, targetStillAvailable: true))
        check("removing the key prevents the confirmed command", !run.mayExecute(
            currentQuery: run.query, enabled: true, hasKey: false, targetStillAvailable: true))
        check("hiding the command prevents the confirmed command", !run.mayExecute(
            currentQuery: run.query, enabled: true, hasKey: true, targetStillAvailable: false))
        run.resumeChoosing()
        check("canceling a dialog returns to choices", run.mayChoose(
            currentQuery: run.query, isLauncherVisible: true, enabled: true, hasKey: true,
            currentCandidates: current))
    }

    static func windowMeaningsDistinguishSimilarCommands() {
        check(
            "Last Third is explicitly rightmost",
            NaturalCommandWindowMeaning.describe(.lastThird).contains("rightmost third"))
        check(
            "Move Right does not resize",
            NaturalCommandWindowMeaning.describe(.moveRight).contains("without resizing"))
        check(
            "every window command has a meaning",
            WindowCommand.ID.allCases.allSatisfy {
                !NaturalCommandWindowMeaning.describe($0).isEmpty
            })
    }

    static func decode(
        choice: String, confidence: Double, probabilities: [String: Double], relevance: Double = 0.95
    ) -> NaturalCommand.ChoiceAnswer {
        let probabilityData = probabilities.map { "\"\($0.key)\":\($0.value)" }
            .joined(separator: ",")
        let command = "\"type\":\"choice\",\"choice\":\"\(choice)\",\"confidence\":\(confidence)"
        let json = """
            {"answers":{"command":{\(command),"probabilities":{\(probabilityData)}},
            "related":{"type":"noul","noul":\(relevance)}}}
            """
        do {
            return try NaturalCommand.decodeChoiceAnswer(from: Data(json.utf8))
        } catch {
            fatalError("Fixture did not decode: \(error)")
        }
    }
}
