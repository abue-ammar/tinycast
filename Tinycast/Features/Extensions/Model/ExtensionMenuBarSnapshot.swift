import Foundation

struct ExtensionMenuBarSnapshot: Codable, Sendable, Equatable {
    let title: String?
    let tooltip: String?
    let iconJSON: String?
    let hasMenu: Bool

    init(node: RenderNode) {
        title = node.string("title")
        tooltip = node.string("tooltip")
        if let value = node.props["icon"],
            let data = try? JSONSerialization.data(withJSONObject: value.jsonValue, options: .fragmentsAllowed)
        {
            iconJSON = String(bytes: data, encoding: .utf8)
        } else {
            iconJSON = nil
        }
        hasMenu = !node.children.isEmpty
    }

    var icon: RenderValue? {
        guard let data = iconJSON?.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        else { return nil }
        return RenderValue(json: value)
    }
}
