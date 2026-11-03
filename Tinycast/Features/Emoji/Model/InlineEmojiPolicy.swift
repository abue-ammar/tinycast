import Foundation

struct InlineEmojiPolicy: Sendable {
    enum Input: Equatable, Sendable {
        case text(String)
        case deleteBackward
        case move(Int)
        case accept
        case escape
        case reset
    }

    enum Effect: Equatable, Sendable {
        case search(String)
        case move(Int)
        case insert(String)
        case dismiss
    }

    struct Decision: Equatable, Sendable {
        let effect: Effect?
        let consumesKey: Bool
    }

    static let maximumQueryLength = 64
    static let timeout: TimeInterval = 15

    private(set) var query: String?
    private var previousCharacter: Character?
    private var lastInputAt: Date?

    mutating func process(_ input: Input, at now: Date, hasResults: Bool) -> Decision {
        if let lastInputAt, now.timeIntervalSince(lastInputAt) > Self.timeout { reset() }
        lastInputAt = now
        switch input {
        case .text(let text):
            return processText(text)
        case .deleteBackward:
            guard var query else { previousCharacter = nil; return Decision(effect: nil, consumesKey: false) }
            guard !query.isEmpty else { return dismiss() }
            query.removeLast()
            self.query = query
            return Decision(effect: .search(query), consumesKey: false)
        case .move(let offset):
            guard query != nil, hasResults else { return dismiss() }
            return Decision(effect: .move(offset), consumesKey: true)
        case .accept:
            guard let query, hasResults else { return dismiss() }
            reset()
            return Decision(effect: .insert(query), consumesKey: true)
        case .escape:
            let wasOpen = query != nil
            reset()
            return Decision(effect: wasOpen ? .dismiss : nil, consumesKey: wasOpen)
        case .reset:
            return dismiss()
        }
    }

    mutating func reset() {
        query = nil
        previousCharacter = nil
        lastInputAt = nil
    }

    static func canStart(after character: Character?) -> Bool {
        guard let character else { return true }
        return character.isWhitespace || "([{\"'".contains(character)
    }

    private mutating func processText(_ text: String) -> Decision {
        let previous = previousCharacter
        previousCharacter = text.last
        if text == ":", query == nil, Self.canStart(after: previous) {
            query = ""
            return Decision(effect: .search(""), consumesKey: false)
        }
        guard let query else { return Decision(effect: nil, consumesKey: false) }
        let next = query + text
        guard !text.isEmpty, next.count <= Self.maximumQueryLength,
            text.allSatisfy({ $0.isLetter || $0.isNumber || "_+- ".contains($0) }),
            !next.hasPrefix(" "), !next.contains("  ")
        else { return dismiss() }
        self.query = next
        return Decision(effect: .search(next), consumesKey: false)
    }

    private mutating func dismiss() -> Decision {
        let wasOpen = query != nil
        query = nil
        return Decision(effect: wasOpen ? .dismiss : nil, consumesKey: false)
    }
}
