import Foundation

enum SnippetKeywordListenerStatus: Equatable, Sendable {
    case off
    case needsAccessibility
    case active
}

struct SnippetKeywordLifecyclePolicy: Sendable {
    enum TapState: Equatable, Sendable {
        case absent
        case disabled
        case active
    }

    enum TapAction: Equatable, Sendable {
        case none
        case install
        case reenable
        case tearDown
    }

    struct Decision: Equatable, Sendable {
        let status: SnippetKeywordListenerStatus
        let tapAction: TapAction
    }

    static func decide(
        isRequested: Bool,
        isSessionActive: Bool,
        hasAccessibility: Bool,
        tapState: TapState
    ) -> Decision {
        guard isRequested else {
            return Decision(
                status: .off,
                tapAction: tapState == .absent ? .none : .tearDown)
        }
        guard isSessionActive, hasAccessibility else {
            return Decision(
                status: .needsAccessibility,
                tapAction: tapState == .absent ? .none : .tearDown)
        }

        switch tapState {
        case .absent:
            return Decision(status: .needsAccessibility, tapAction: .install)
        case .disabled:
            return Decision(status: .needsAccessibility, tapAction: .reenable)
        case .active:
            return Decision(status: .active, tapAction: .none)
        }
    }
}

struct SnippetKeywordPolicy: Sendable {
    struct Keyword: Equatable, Sendable {
        let snippetID: StoredSnippet.ID
        let value: String
        let deletionCount: Int

        init(snippetID: StoredSnippet.ID, value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            self.snippetID = snippetID
            self.value = trimmed.lowercased()
            deletionCount = trimmed.count
        }
    }

    struct Match: Equatable, Sendable {
        let snippetID: StoredSnippet.ID
        let keyword: String
        let deletionCount: Int
    }

    enum Input: Equatable, Sendable {
        case text(String)
        case deleteBackward
        case reset
        case ignored
    }

    static let timeout: TimeInterval = 15
    static let maximumBufferLength = 256

    private(set) var keywords: [Keyword] = []
    private(set) var buffer = ""
    private var lastInputAt: Date?

    init(keywords: [Keyword] = []) {
        update(keywords)
    }

    mutating func update(_ keywords: [Keyword]) {
        self.keywords = keywords
            .filter { !$0.value.isEmpty && $0.deletionCount <= Self.maximumBufferLength }
            .sorted {
                if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
                return $0.snippetID < $1.snippetID
            }
        reset()
    }

    mutating func process(_ input: Input, at now: Date) -> Match? {
        if case .ignored = input { return nil }
        if let lastInputAt, now.timeIntervalSince(lastInputAt) > Self.timeout {
            reset()
        }

        switch input {
        case .ignored:
            return nil
        case .reset:
            reset()
            return nil
        case .deleteBackward:
            lastInputAt = now
            if !buffer.isEmpty { buffer.removeLast() }
            return nil
        case .text(let text):
            lastInputAt = now
            buffer.append(text)
            if buffer.count > Self.maximumBufferLength {
                buffer.removeFirst(buffer.count - Self.maximumBufferLength)
            }
        }

        let normalizedBuffer = buffer.lowercased()
        guard let keyword = keywords.first(where: { normalizedBuffer.hasSuffix($0.value) }) else {
            return nil
        }
        reset()
        return Match(
            snippetID: keyword.snippetID,
            keyword: keyword.value,
            deletionCount: keyword.deletionCount)
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        lastInputAt = nil
    }

    static func classifyInput(
        text: String?,
        isSynthetic: Bool,
        secureEventInputEnabled: Bool,
        isFlagsChanged: Bool,
        isKeyDown: Bool,
        hasCommandOrControl: Bool,
        isResetKey: Bool,
        isDeleteBackward: Bool
    ) -> Input {
        if isSynthetic { return .ignored }
        if secureEventInputEnabled || hasCommandOrControl || isResetKey { return .reset }
        if isFlagsChanged { return .ignored }
        guard isKeyDown else { return .ignored }
        if isDeleteBackward { return .deleteBackward }
        guard let text else { return .reset }
        return .text(text)
    }
}
