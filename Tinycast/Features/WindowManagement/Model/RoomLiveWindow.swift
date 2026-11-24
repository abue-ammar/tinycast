// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// One window the sweep found. A handle, not an `AXUIElement`: this layer stays pure.
struct RoomLiveWindow: Equatable, Sendable {
    var handle: Int
    var bundleID: String
    var appName: String
    var title: String
    var windowID: UInt32?
    var frame: CGRect
    var isMinimized = false
    var isAppHidden = false
    /// The window server's front-to-back order; `.max` when it is not on screen.
    var frontRank = Int.max
    var appURL: URL?
}
