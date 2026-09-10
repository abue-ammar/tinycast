import Foundation

struct CustomQuickAction: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "quick-action:"
    static let sfSymbol = "wand.and.stars"

    let id: UUID
    var name: String
    var iconSymbol: String?
    var instructions: String
    var previewsResult: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, iconSymbol: String? = nil, instructions: String,
        previewsResult: Bool = true, createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.instructions = instructions
        self.previewsResult = previewsResult
        self.createdAt = createdAt
    }

    var symbol: String { iconSymbol ?? Self.sfSymbol }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    static func precedes(_ lhs: CustomQuickAction, _ rhs: CustomQuickAction) -> Bool {
        lhs.createdAt != rhs.createdAt
            ? lhs.createdAt < rhs.createdAt
            : lhs.id.uuidString < rhs.id.uuidString
    }
}

enum CustomQuickActionError: Error, LocalizedError, Equatable {
    case emptyName
    case emptyInstructions
    case invalidCharacter
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Give the action a name."
        case .emptyInstructions: return "Tell the model what the action should do."
        case .invalidCharacter: return "The name contains a character Tinycast can't store."
        case .storageUnavailable: return "Tinycast couldn't save to its actions file."
        }
    }
}
