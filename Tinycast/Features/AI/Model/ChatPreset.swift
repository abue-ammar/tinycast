import Foundation

/// A saved way to start a chat: its own instructions, and optionally its own model and tools.
struct ChatPreset: Codable, Hashable, Identifiable, Sendable {
    static let sfSymbol = "text.bubble"

    /// What a started chat keeps of its preset, and the tools it last sent with.
    struct Stamp: Codable, Equatable, Sendable {
        let presetID: UUID
        let name: String
        let symbol: String
        let instructions: String
        var toolScope: ChatToolScope
    }

    let id: UUID
    var name: String
    var iconSymbol: String?
    var instructions: String
    /// Nil follows AI Chat's default model.
    var model: AIModelSelection?
    var toolScope: ChatToolScope
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, iconSymbol: String? = nil, instructions: String,
        model: AIModelSelection? = nil, toolScope: ChatToolScope = ChatToolScope(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.instructions = instructions
        self.model = model
        self.toolScope = toolScope
        self.createdAt = createdAt
    }

    var symbol: String { iconSymbol ?? Self.sfSymbol }

    var stamp: Stamp {
        Stamp(
            presetID: id, name: name, symbol: symbol, instructions: instructions,
            toolScope: toolScope)
    }

    static func precedes(_ lhs: ChatPreset, _ rhs: ChatPreset) -> Bool {
        lhs.createdAt != rhs.createdAt
            ? lhs.createdAt < rhs.createdAt
            : lhs.id.uuidString < rhs.id.uuidString
    }
}

enum ChatPresetError: Error, LocalizedError, Equatable {
    case emptyName
    case emptyInstructions
    case invalidCharacter
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Give the preset a name.")
        case .emptyInstructions: return String(localized: "Tell the model what these chats are for.")
        case .invalidCharacter:
            return String(localized: "The name contains a character Tinycast can't store.")
        case .storageUnavailable: return String(localized: "Tinycast couldn't save to its presets file.")
        }
    }
}
