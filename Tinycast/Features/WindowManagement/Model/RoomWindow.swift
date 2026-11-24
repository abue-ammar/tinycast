// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// One window a room holds, and what finds it again.
struct RoomWindow: Codable, Hashable, Sendable {
    var bundleID: String
    var appName: String
    /// What finds the window again once its ID is gone, after its app relaunches.
    var title: String
    /// The window server's number; it lasts only while the window stays open.
    var windowID: UInt32?
    /// Where it sits under `.saved`, as a fraction of the display's visible frame.
    var unitFrame: CGRect
    var cell: RoomGrid.Cell?

    init(
        bundleID: String, appName: String, title: String, windowID: UInt32? = nil,
        unitFrame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), cell: RoomGrid.Cell? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.windowID = windowID
        self.unitFrame = unitFrame
        self.cell = cell
    }

    /// An open window as it sits now, on a display whose visible frame is `visible`.
    init(_ window: RoomLiveWindow, in visible: CGRect) {
        self.init(
            bundleID: window.bundleID, appName: window.appName, title: window.title,
            windowID: window.windowID, unitFrame: Self.unitFrame(of: window.frame, in: visible))
    }

    /// Names no window, so any window of its app fills it.
    var isWholeApp: Bool { windowID == nil && title.isEmpty }

    /// Four decimal places, so a stored fraction reads cleanly and resolves to the same point.
    static func unitFrame(of frame: CGRect, in visible: CGRect) -> CGRect {
        guard visible.width > 0, visible.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        func fraction(_ value: CGFloat) -> CGFloat { (value * 10_000).rounded() / 10_000 }
        return CGRect(
            x: fraction((frame.minX - visible.minX) / visible.width),
            y: fraction((frame.minY - visible.minY) / visible.height),
            width: fraction(frame.width / visible.width),
            height: fraction(frame.height / visible.height))
    }

    func frame(in visible: CGRect) -> CGRect {
        WindowPlacementEngine.rounded(
            CGRect(
                x: visible.minX + unitFrame.minX * visible.width,
                y: visible.minY + unitFrame.minY * visible.height,
                width: unitFrame.width * visible.width,
                height: unitFrame.height * visible.height))
    }

    // Hand-written, so an added field keeps stored rooms and older backups readable.
    private enum CodingKeys: String, CodingKey {
        case bundleID, appName, title, windowID, unitFrame, cell
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? bundleID
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        windowID = try container.decodeIfPresent(UInt32.self, forKey: .windowID)
        unitFrame =
            try container.decodeIfPresent(CGRect.self, forKey: .unitFrame)
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        cell = try container.decodeIfPresent(RoomGrid.Cell.self, forKey: .cell)
    }
}
