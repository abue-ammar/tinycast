import Foundation

enum DictationMode: String, CaseIterable, Identifiable, Sendable {
    case pushToTalk
    case toggle

    var id: Self { self }
    var title: String {
        self == .pushToTalk ? String(localized: "Hold to talk") : String(localized: "Press to start or stop")
    }
}
