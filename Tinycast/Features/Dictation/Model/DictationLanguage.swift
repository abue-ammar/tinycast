import Foundation

enum DictationLanguage: String, CaseIterable, Identifiable, Sendable {
    case arabic = "Arabic", cantonese = "Cantonese", chinese = "Chinese", czech = "Czech"
    case danish = "Danish", dutch = "Dutch", english = "English", filipino = "Filipino"
    case finnish = "Finnish", french = "French", german = "German", greek = "Greek"
    case hindi = "Hindi", hungarian = "Hungarian", indonesian = "Indonesian", italian = "Italian"
    case japanese = "Japanese", korean = "Korean", macedonian = "Macedonian", malay = "Malay"
    case persian = "Persian", polish = "Polish", portuguese = "Portuguese", romanian = "Romanian"
    case russian = "Russian", spanish = "Spanish", swedish = "Swedish", thai = "Thai"
    case turkish = "Turkish", vietnamese = "Vietnamese"

    var id: Self { self }

    /// The raw value is what the model is prompted with; the picker shows the reader's own name.
    func displayName(locale: Locale) -> String { locale.localizedString(forLanguageCode: code) ?? rawValue }

    private var code: String {
        switch self {
        case .arabic: "ar"
        case .cantonese: "yue"
        case .chinese: "zh"
        case .czech: "cs"
        case .danish: "da"
        case .dutch: "nl"
        case .english: "en"
        case .filipino: "fil"
        case .finnish: "fi"
        case .french: "fr"
        case .german: "de"
        case .greek: "el"
        case .hindi: "hi"
        case .hungarian: "hu"
        case .indonesian: "id"
        case .italian: "it"
        case .japanese: "ja"
        case .korean: "ko"
        case .macedonian: "mk"
        case .malay: "ms"
        case .persian: "fa"
        case .polish: "pl"
        case .portuguese: "pt"
        case .romanian: "ro"
        case .russian: "ru"
        case .spanish: "es"
        case .swedish: "sv"
        case .thai: "th"
        case .turkish: "tr"
        case .vietnamese: "vi"
        }
    }
}
