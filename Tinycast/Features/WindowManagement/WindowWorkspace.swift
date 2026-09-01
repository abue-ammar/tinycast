import CoreGraphics
import Foundation

/// A named snapshot of windows, expressed relative to each screen's usable area.
struct WindowWorkspace: Codable, Equatable, Identifiable, Sendable {
    struct Window: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let bundleID: String
        let screenID: UInt32
        let frame: NormalizedFrame

        init(id: UUID = UUID(), bundleID: String, screenID: UInt32, frame: NormalizedFrame) {
            self.id = id
            self.bundleID = bundleID
            self.screenID = screenID
            self.frame = frame
        }
    }

    /// A frame relative to `NSScreen.visibleFrame`, independent of the display's resolution.
    struct NormalizedFrame: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        init?(frame: CGRect, in visibleFrame: CGRect) {
            guard visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }
            x = (frame.minX - visibleFrame.minX) / visibleFrame.width
            y = (frame.minY - visibleFrame.minY) / visibleFrame.height
            width = frame.width / visibleFrame.width
            height = frame.height / visibleFrame.height
        }

        /// Reconstitutes a reachable rect even if a saved layout no longer fits the display.
        func frame(in visibleFrame: CGRect) -> CGRect? {
            guard
                visibleFrame.width > 0, visibleFrame.height > 0,
                x.isFinite, y.isFinite, width.isFinite, height.isFinite,
                width >= 0, height >= 0
            else { return nil }

            let raw = CGRect(
                x: visibleFrame.minX + CGFloat(x) * visibleFrame.width,
                y: visibleFrame.minY + CGFloat(y) * visibleFrame.height,
                width: min(CGFloat(width) * visibleFrame.width, visibleFrame.width),
                height: min(CGFloat(height) * visibleFrame.height, visibleFrame.height))
            guard raw.width.isFinite, raw.height.isFinite else { return nil }
            return CGRect(
                x: min(max(raw.minX, visibleFrame.minX), visibleFrame.maxX - raw.width),
                y: min(max(raw.minY, visibleFrame.minY), visibleFrame.maxY - raw.height),
                width: raw.width, height: raw.height)
        }
    }

    let id: UUID
    var name: String
    var windows: [Window]

    init(id: UUID = UUID(), name: String, windows: [Window]) {
        self.id = id
        self.name = name
        self.windows = windows
    }
}
