import Foundation

struct ExtensionAppearance: Codable, Equatable, Hashable, Sendable {
    var symbol: String

    static let fallback = ExtensionAppearance(symbol: "puzzlepiece.extension")
}
