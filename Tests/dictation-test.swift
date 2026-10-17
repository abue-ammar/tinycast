import Foundation

@main
struct DictationTest {
    static func main() {
        let locale = Locale(identifier: "en_US")
        func check(_ actual: String, _ expected: String) {
            guard actual == expected else {
                print("Expected \(expected.debugDescription), got \(actual.debugDescription)")
                exit(1)
            }
        }

        typealias Context = DictationTextFormatter.Context
        check(DictationTextFormatter.format("  Hello. \n", context: nil), "Hello.")
        check(DictationTextFormatter.format("hello", context: Context(before: "", after: "")), "Hello")
        check(DictationTextFormatter.format("World", context: Context(before: "Hello", after: "")), " world")
        check(DictationTextFormatter.format("world", context: Context(before: "Hello.", after: "")), " World")
        check(DictationTextFormatter.format("hello", context: Context(before: "Wait. ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("hello", context: Context(before: "Wait\n  ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("World", context: Context(before: "Hello ", after: "again")),
            "world ")
        check(DictationTextFormatter.format("hello", context: Context(before: "(", after: ")")), "hello")
        check(
            DictationTextFormatter.format("application", context: Context(before: "l’", after: "")),
            "application")
        check(
            DictationTextFormatter.format(
                "Tinycast", context: Context(before: "Use", after: "again"),
                adaptCapitalization: false), " Tinycast ")
        check(
            DictationTextFormatter.format(
                "world", context: Context(before: "Hello.", after: ""),
                adaptCapitalization: false), " world")
        check(
            DictationTextFormatter.format(
                "hello", context: Context(before: "", after: ""),
                adaptCapitalization: false), "hello")
        check(
            DictationTextFormatter.format(
                "World.", context: Context(before: "Hello ", after: ")"),
                adaptCapitalization: false), "World.")
        let document = "prefix. Text to replace suffix"
        check(
            DictationTextFormatter.format(
                "world",
                context: Context(
                    before: document.prefix(7), after: document.suffix(6))), " World ")
        check(DictationTextFormatter.stripEcho(" world peace", after: "Hello world"), " peace")
        check(DictationTextFormatter.stripEcho("theatre tickets", after: "said the"), "theatre tickets")
        check(DictationTextFormatter.stripEcho(" world", after: "Hello world"), "")
        check(DictationTextFormatter.stripEcho("good morning", after: "Hello world"), "good morning")
        check(DictationTextFormatter.stripEcho(" hello", after: ""), " hello")
        check(
            DictationTextFormatter.stripEcho("Für, Jonathan", after: "kein kuchen für"),
            " Jonathan")
        check(
            DictationTextFormatter.stripEcho("ein Kuchen für Jonathan", after: "aber kein Kuchen für"),
            " Jonathan")
        check(
            DictationTextFormatter.stripEcho("äh also weiter gehts", after: "und dann"),
            "äh also weiter gehts")
        check(DictationModel.redux.folderName, "parakeet-redux")
        check(DictationModel.ultra.folderName, "parakeet-ultra")
        check(DictationModel.redux.title, "Parakeet · Redux")
        check(DictationModel.ultra.title, "Parakeet · Ultra")
        check(DictationIdleRelease.allCases.map(\.rawValue).description, "[0, 1, 2, 5, 10, 15, 20, 30, 60]")
        check(DictationIdleRelease.never.title(locale: locale), "Never")
        check(DictationIdleRelease.oneHour.title(locale: locale), "1 hour")
        check(DictationIdleRelease.oneHour.title(locale: Locale(identifier: "fr_FR")), "1\u{00a0}heure")
        check(DictationLanguage.english.displayName(locale: locale), "English")
        check(DictationLanguage.english.displayName(locale: Locale(identifier: "de_DE")), "Englisch")
        check(DictationLanguage.english.rawValue, "English")
        check(DictationModel.qwenSmall.folderName, "qwen-0.6b")
        check(DictationModel.qwenLarge.folderName, "qwen-1.7b")
        for family in DictationModel.Family.allCases {
            guard DictationModel.allCases.contains(where: { $0.family == family }) else {
                fatalError("Every engine should expose at least one model")
            }
        }
        for model in DictationModel.allCases {
            guard !model.components.isEmpty, model.revision.count == 40,
                model.requiredFiles.isSuperset(of: model.components)
            else {
                fatalError("Model installation metadata is incomplete")
            }
            if let configuration = model.parakeetConfiguration {
                guard model.family == .parakeet, configuration.blankToken == 8192,
                    configuration.encoderUsesGPU == (model == .redux),
                    model.components.contains(configuration.joint + ".mlmodelc")
                else {
                    fatalError("Parakeet download and inference disagree")
                }
            } else if !model.isQwen {
                fatalError("Missing Parakeet decoding configuration")
            }
        }
        print("Dictation text formatting passed")
    }
}
