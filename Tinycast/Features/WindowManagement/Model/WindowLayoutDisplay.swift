import Foundation

/// Which screen an entry targets, identified so it survives a reboot and a reconnect.
struct WindowLayoutDisplay: Codable, Hashable, Sendable {
    /// `CGDisplayCreateUUIDFromDisplayID`, stringified by the service layer, never read here.
    var uuid: String
    /// `NSScreen.localizedName` at authoring time, so an absent display can still name itself.
    var name: String

    init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Display"
    }
}
