import Foundation

/// How many rounds of tool calls one reply may make before it is treated as stuck.
enum AIToolRounds: Int, CaseIterable, Identifiable, Sendable {
    case ten = 10
    case twentyFive = 25
    case fifty = 50
    case hundred = 100
    case unlimited = -1

    var id: Int { rawValue }

    var title: String { limit.map { "\($0)" } ?? "Unlimited" }

    /// `nil` is no cap: the reply runs until the model stops asking or Stop is pressed.
    var limit: Int? { self == .unlimited ? nil : rawValue }
}
