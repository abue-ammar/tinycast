import Foundation

/// One settled render as plain values, so restoring the item needs no runtime.
struct ExtensionMenuBarSnapshot: Codable, Sendable, Equatable {
    let title: String?
    let tooltip: String?
    let iconJSON: String?
    let hasMenu: Bool
}
