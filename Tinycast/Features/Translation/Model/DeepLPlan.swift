import Foundation

enum DeepLPlan: String, CaseIterable, Codable, Sendable {
    case free
    case pro

    var title: String {
        switch self {
        case .free: "Free"
        case .pro: "Pro"
        }
    }

    var baseURL: URL {
        switch self {
        case .free: URL(string: "https://api-free.deepl.com")!
        case .pro: URL(string: "https://api.deepl.com")!
        }
    }

    static let freeAccount = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let proAccount = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))

    var account: UUID { self == .free ? Self.freeAccount : Self.proAccount }
}
