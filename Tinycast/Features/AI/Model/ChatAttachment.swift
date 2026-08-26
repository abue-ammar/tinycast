import Foundation

struct ChatAttachment: Identifiable, Sendable, Equatable {
    let id: UUID
    let image: AIImage
    let name: String

    init(id: UUID = UUID(), image: AIImage, name: String) {
        self.id = id
        self.image = image
        self.name = name
    }
}

enum ChatAttachmentRefusal: Sendable {
    case count
    case size

    var message: String {
        switch self {
        case .count:
            return "Only \(AIAttachmentBudget.maxCount) images can be attached to a message."
        case .size:
            return "That image exceeds the attachment size limit."
        }
    }
}
