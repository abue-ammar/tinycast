import Foundation

/// How many rounds of tool calls one reply may make before it is treated as stuck.
enum AIToolRounds: Int, CaseIterable, Identifiable, Sendable {
    case ten = 10
    case twentyFive = 25
    case fifty = 50
    case hundred = 100

    var id: Int { rawValue }

    var title: String { "\(rawValue)" }
}
