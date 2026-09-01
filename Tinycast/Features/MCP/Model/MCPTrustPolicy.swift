import Foundation

/// Whether one call may run, from the server's standing trust and what this chat already granted.
enum MCPTrustPolicy {
    enum Verdict: Equatable, Sendable {
        case allow
        case ask
        case refuse
    }

    static func decide(trust: MCPTrust, isGrantedForChat: Bool) -> Verdict {
        switch trust {
        case .never: return .refuse
        case .always: return .allow
        case .ask: return isGrantedForChat ? .allow : .ask
        }
    }
}

/// What the reader chose in the dialog. Only Settings can withhold a server for good.
enum MCPTrustChoice: Equatable, Sendable {
    case always
    case thisChat
    case refuse
}
