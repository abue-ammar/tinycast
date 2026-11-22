import Foundation

/// What a backup leaves out on purpose, listed so no feature looks forgotten.
enum BackupExclusion: CaseIterable, Sendable {
    case extensions, quickActions, chatPresets, chatHistory, mcpServers, dictation, credentials

    var title: String {
        switch self {
        case .extensions: String(localized: "Extensions")
        case .quickActions: String(localized: "Quick Actions")
        case .chatPresets: String(localized: "Chat Presets")
        case .chatHistory: String(localized: "AI Chat History")
        case .mcpServers: String(localized: "MCP Servers")
        case .dictation: String(localized: "Dictation")
        case .credentials: String(localized: "Passwords & API Keys")
        }
    }

    var symbol: String {
        switch self {
        case .extensions: "puzzlepiece.extension.fill"
        case .quickActions: "wand.and.sparkles"
        case .chatPresets: "text.bubble.fill"
        case .chatHistory: "bubble.left.fill"
        case .mcpServers: "server.rack"
        case .dictation: "waveform"
        case .credentials: "key.fill"
        }
    }

    var tint: IconTint {
        switch self {
        case .extensions: .green
        case .quickActions: .indigo
        case .chatPresets, .chatHistory, .mcpServers: .purple
        case .dictation: .pink
        case .credentials: .gray
        }
    }

    var detail: String {
        switch self {
        case .extensions:
            String(localized: "Extensions are third-party code, so they and their data stay on this Mac.")
        case .quickActions:
            String(localized: "An import must never change what an action does to your text.")
        case .chatPresets:
            String(localized: "Standing instructions must never arrive on another Mac unread.")
        case .chatHistory: String(localized: "Conversations stay on the Mac that had them.")
        case .mcpServers:
            String(localized: "A server runs code and depends on credentials saved on this Mac.")
        case .dictation: String(localized: "Models and microphone access belong to this Mac.")
        case .credentials: String(localized: "Kept in this Mac's Keychain and never written to a file.")
        }
    }
}
