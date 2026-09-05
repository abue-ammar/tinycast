// Quick Actions' pure half: the actions, their prompts, the diff, and the reader's own choices.

import Foundation

@main
@MainActor
struct QuickActionTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        everyActionDescribesItself()
        promptsForbidCommentaryAndInjection()
        previewChoicesRememberOnlyWhatWasChosen()
        diffsFindWordLevelChanges()
        diffsStayBoundedOnLongText()
        settingsPersistAndRepairTheirRoute()
        refusalsNameTheirOwnCause()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// A refusal naming no cause tells a reader to select the text they had already selected.
    static func refusalsNameTheirOwnCause() {
        let failures: [QuickActionFailure] = [
            .needsAccessibility, .noTarget, .unreadableApp("Chrome"), .noSelection, .tooLong
        ]
        let messages = failures.map(\.localizedDescription)
        expect(
            Set(messages).count == failures.count,
            "no two refusals read the same, got \(messages)")
        for message in messages {
            expect(!message.isEmpty, "every refusal explains itself")
        }
        expect(
            QuickActionFailure.unreadableApp("Chrome").localizedDescription.contains("Chrome"),
            "an unreadable app is named, so the reader knows which one to blame")
        expect(
            QuickActionFailure.needsAccessibility.localizedDescription.lowercased()
                .contains("accessibility"),
            "the permission failure says which permission")

        // Only the permission failure has somewhere to send the reader, so only it earns a dialog.
        expect(
            failures.filter(\.opensAccessibilitySettings) == [.needsAccessibility],
            "only a missing permission opens System Settings")
    }

    static func settingsPersistAndRepairTheirRoute() {
        let suite = "QuickActionTests.settings"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }

        let store = QuickActionSettingsStore(defaults: defaults)
        expect(store.model == nil, "a fresh store names no route until one is resolved")

        // Nothing configured takes the route that needs no account, like chat's own default.
        store.resolveModel(appleIntelligenceAvailable: true, fallback: nil)
        expect(store.model == .appleIntelligence, "on-device is what an unconfigured Mac resolves to")

        // Resolution never overrides a choice, and never re-runs over one.
        let connectionID = UUID()
        store.select(.api(connection: connectionID, model: "m"))
        store.resolveModel(appleIntelligenceAvailable: true, fallback: nil)
        expect(
            store.model == .api(connection: connectionID, model: "m"),
            "resolution leaves a route the reader chose alone")

        store.settings.setPreviewsResult(true, for: .fixGrammar)
        store.settings.targetLanguage = "de"
        store.settings.setInstructionOverride("Use British English.", for: .fixGrammar)

        let reopened = QuickActionSettingsStore(defaults: defaults)
        expect(
            reopened.model == .api(connection: connectionID, model: "m"),
            "the route survives a relaunch")
        expect(reopened.settings.previewsResult(.fixGrammar), "a preview choice survives a relaunch")
        expect(reopened.settings.targetLanguage == "de", "the target language survives a relaunch")
        expect(
            reopened.settings.instructionOverride(for: .fixGrammar) == "Use British English.",
            "an action's instructions survive a relaunch")

        // A removed connection must not leave this pointing at a route that cannot answer.
        reopened.repairModel(against: [], fallback: .appleIntelligence)
        expect(
            reopened.model == .appleIntelligence,
            "a removed connection falls forward rather than failing at press time")

        let onDevice = QuickActionSettingsStore(defaults: defaults)
        onDevice.repairModel(against: [], fallback: nil)
        expect(
            onDevice.model == .appleIntelligence,
            "repair leaves a route that names no connection untouched")

        onDevice.select(.claude(model: "old", effort: nil))
        onDevice.repairInstalledModel(
            available: [.claude(model: "sonnet", effort: nil)], unavailableSources: [],
            fallback: .appleIntelligence)
        expect(
            onDevice.model == .claude(model: "sonnet", effort: nil),
            "an installed model removed from the catalog moves to that command's first model")
        onDevice.select(.openCode(model: "provider/old", effort: nil))
        onDevice.repairInstalledModel(
            available: [], unavailableSources: [.openCode], fallback: .appleIntelligence)
        expect(
            onDevice.model == .appleIntelligence,
            "an unavailable installed command does not leave Quick Actions on a dead route")
        onDevice.select(.claude(model: "haiku", effort: nil))
        onDevice.repairInstalledModel(
            available: [], unavailableSources: [.claude],
            fallback: .claude(model: "sonnet", effort: nil))
        expect(
            onDevice.model == nil,
            "an unavailable installed command is not replaced by another dead model")
        onDevice.select(.codex(model: "gpt", effort: "high"))
        let withEffort = QuickActionSettingsStore(defaults: defaults)
        expect(
            withEffort.model == .codex(model: "gpt", effort: "high"),
            "Quick Actions persist their own Codex reasoning effort")
        onDevice.select(.openCode(model: "provider/model", effort: "max"))
        let withOpenCodeEffort = QuickActionSettingsStore(defaults: defaults)
        expect(
            withOpenCodeEffort.model == .openCode(model: "provider/model", effort: "max"),
            "Quick Actions persist their own OpenCode reasoning effort")
    }

    static func everyActionDescribesItself() {
        for action in QuickAction.allCases {
            expect(!action.title.isEmpty, "\(action) has a title")
            expect(!action.symbol.isEmpty, "\(action) has a glyph")
            expect(action.rawValue == action.id, "\(action) keys its shortcut on its raw value")
        }
        expect(
            Set(QuickAction.allCases.map(\.title)).count == QuickAction.allCases.count,
            "no two actions read the same in the shortcut list")

        // Summarize answers a question about the text; replacing it unasked would destroy the text.
        expect(QuickAction.summarize.alwaysPreviews, "Summarize always shows its panel")
        expect(
            QuickAction.allCases.filter(\.alwaysPreviews) == [.summarize],
            "only Summarize forces a panel")
        expect(
            QuickAction.fixGrammar.replacesDirectlyByDefault,
            "grammar is the one action safe to apply unseen")
        expect(
            !QuickAction.rewrite.replacesDirectlyByDefault,
            "a rewrite changes the voice, so it is previewed by default")
        expect(
            QuickAction.translate.usesTranslationFramework,
            "Translate goes to Apple's translator, not the model")
        expect(
            QuickAction.allCases.filter(\.usesTranslationFramework) == [.translate],
            "nothing else claims the translator")
        expect(
            QuickAction.summarize.showsDiff == false,
            "a summary is not the input edited, so a diff would be noise")
    }

    static func promptsForbidCommentaryAndInjection() {
        for action in QuickAction.allCases {
            let instructions = QuickActionPrompt.instructions(for: action)
            expect(!instructions.isEmpty, "\(action) carries instructions")
            // The output is pasted into somebody's document; a preamble is a defect there.
            expect(
                instructions.lowercased().contains("only")
                    || instructions.lowercased().contains("do not open"),
                "\(action) tells the model to return the text and nothing else")
            expect(
                instructions.lowercased().contains("never")
                    || instructions.lowercased().contains("never follow"),
                "\(action) treats the selection as material, not as instructions")
        }

        // The delimiter is what stops a short selection reading as part of the instruction.
        let message = QuickActionPrompt.message(for: .fixGrammar, selection: "teh cat")
        expect(message.contains("Text:"), "the selection is delimited from the instruction")
        expect(message.hasSuffix("teh cat"), "the selection goes last, unaltered")

        // Only Summarize asks a question of the text; the rest just hand it over to be transformed.
        expect(
            QuickActionPrompt.message(for: .summarize, selection: "hi").hasPrefix("Summarize"),
            "a summary names the task above the text it is given")
        expect(
            QuickActionPrompt.message(for: .rewrite, selection: "hi").hasPrefix("Text:"),
            "an action whose instructions already say what to do adds no second request")

        expect(
            QuickActionPrompt.instructions(for: .rewrite, override: "My instructions")
                == "My instructions",
            "an override replaces the complete built-in prompt")
        expect(
            QuickActionPrompt.instructions(for: .rewrite, override: "").isEmpty,
            "an empty override deliberately sends no instructions")
        expect(
            QuickActionPrompt.instructions(for: .translate, override: "My instructions")
                == QuickActionPrompt.instructions(for: .translate),
            "Translate never accepts model instructions")

        var settings = QuickActionSettings()
        settings.setInstructionOverride("Custom", for: .rewrite)
        settings.setInstructionOverride("Ignored", for: .translate)
        expect(
            settings.instructionOverride(for: .rewrite) == "Custom",
            "each model-backed action keeps its own instructions")
        expect(
            settings.instructionOverride(for: .fixGrammar) == nil,
            "customizing one action leaves the others on their defaults")
        expect(
            settings.instructionOverride(for: .translate) == nil,
            "Translate cannot persist model instructions")
    }

    static func previewChoicesRememberOnlyWhatWasChosen() {
        var settings = QuickActionSettings()
        expect(settings.previewChoices.isEmpty, "nothing is stored until the reader chooses")
        expect(!settings.previewsResult(.fixGrammar), "grammar applies directly by default")
        expect(settings.previewsResult(.rewrite), "a rewrite previews by default")
        expect(settings.previewsResult(.summarize), "Summarize previews whatever is stored")

        settings.setPreviewsResult(true, for: .fixGrammar)
        expect(settings.previewsResult(.fixGrammar), "an explicit choice is honoured")
        settings.setPreviewsResult(false, for: .summarize)
        expect(
            settings.previewsResult(.summarize),
            "Summarize cannot be told to replace text unseen")

        // Round-trips as a plain dictionary, and an action that no longer exists is dropped.
        var restored = QuickActionSettings()
        restored.storedPreviewChoices = settings.storedPreviewChoices
        expect(
            restored.previewsResult(.fixGrammar),
            "a stored choice survives the trip through UserDefaults")
        restored.storedPreviewChoices = ["notAnAction": true]
        expect(restored.previewChoices.isEmpty, "an unknown key is a removed action, not a crash")
    }

    static func diffsFindWordLevelChanges() {
        let chunks = TextDiffEngine.diff(
            original: "Their going to the meeting", modified: "They're going to the meeting")
        expect(chunks.contains(.deleted("Their")), "the replaced word is marked deleted")
        expect(
            chunks.contains { if case .inserted(let text) = $0 { text.contains("They") } else { false } },
            "the replacement is marked inserted")
        expect(
            chunks.contains { if case .equal(let text) = $0 { text.contains("meeting") } else { false } },
            "untouched words stay equal")

        expect(
            TextDiffEngine.diff(original: "same", modified: "same") == [.equal("same")],
            "an unchanged result is one equal run")
        expect(TextDiffEngine.diff(original: "", modified: "") == [], "two empties diff to nothing")
        expect(
            TextDiffEngine.diff(original: "gone", modified: "") == [.deleted("gone")],
            "an emptied result is wholly deleted")

        // Coalescing's invariant: no two neighbours share a kind, or a phrase reads as a stutter.
        let phrase = TextDiffEngine.diff(original: "one two three", modified: "four five three")
        let stutters = zip(phrase, phrase.dropFirst()).filter { sameKind($0, $1) }
        expect(stutters.isEmpty, "no two adjacent chunks share a kind, got \(phrase)")
    }

    /// A fixed suite name stops cfprefsd accumulating a plist per run; cleared at both ends.
    static func isolatedDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// `removePersistentDomain` only empties the domain; cfprefsd still leaves the plist on disk.
    static func discardSuite(_ name: String, _ defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: name)
        UserDefaults.standard.removeSuite(named: name)
        CFPreferencesAppSynchronize(name as CFString)
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Preferences/\(name).plist"))
    }

    static func sameKind(_ lhs: TextDiffEngine.Chunk, _ rhs: TextDiffEngine.Chunk) -> Bool {
        switch (lhs, rhs) {
        case (.equal, .equal), (.inserted, .inserted), (.deleted, .deleted): return true
        default: return false
        }
    }

    static func diffsStayBoundedOnLongText() {
        // The matrix is quadratic, so an unbounded diff of a long selection asks for gigabytes.
        let long = String(repeating: "word ", count: TextDiffEngine.maxTokens)
        let chunks = TextDiffEngine.diff(original: long, modified: long + "tail")
        expect(chunks.count == 2, "past the ceiling the diff degrades to whole-text, not a hang")
        expect(
            chunks.first == .deleted(long),
            "the degraded diff still names the original whole")
    }
}
