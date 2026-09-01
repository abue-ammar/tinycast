import Foundation

/// A named sequence of existing Tinycast actions.
struct ActionChain: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "action-chain:"
    static let sfSymbol = "point.3.connected.trianglepath.dotted"

    let id: UUID
    var name: String
    var steps: [ActionChainStep]

    init(id: UUID = UUID(), name: String, steps: [ActionChainStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }
}

/// A persisted reference to an action that can run without typed input.
enum ActionChainStep: Codable, Hashable, Sendable {
    case application(bundleID: String)
    case systemAction(id: String)
    case windowCommand(id: String)
    case customCommand(id: UUID)
    case quicklink(id: UUID)
}

enum ActionChainFailure: Error, Sendable {
    case unavailable
}
