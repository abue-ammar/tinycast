import AppKit
import SwiftUI

/// Owns the check-yourself panel: one at a time, and the camera stops with it.
@MainActor
final class CameraPreviewController: NSObject, NSWindowDelegate {
    private let session = CameraPreviewSession()
    private var panel: CameraPreviewPanel?
    private var continuation: CheckedContinuation<Bool, Never>?
    /// Held across the camera warm-up too, so a chord repeating into it cannot stack previews.
    private var presenting = false

    /// The camera settles first: a panel over a starting session shows a black stage.
    func present(meeting: MeetingEvent, now: Date) async -> Bool {
        guard !presenting else { return false }
        presenting = true
        defer { presenting = false }
        let feed = await session.start()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(meeting: meeting, now: now, feed: feed)
        }
    }

    private func show(meeting: MeetingEvent, now: Date, feed: CameraPreviewSession.Feed) {
        let view = CameraPreviewView(
            meeting: meeting, now: now, feed: feed,
            onJoin: { [weak self] in self?.finish(true) },
            onCancel: { [weak self] in self?.finish(false) })
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPreviewPanel(content: hosting)
        panel.delegate = self
        panel.onKey = { [weak self] key in self?.finish(key == .join) }
        self.panel = panel
        place(panel)
        // Non-activating like the palette: key focus without pulling the user out of their app.
        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    private func finish(_ taken: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        let closing = panel
        panel = nil
        closing?.delegate = nil
        closing?.onKey = nil
        continuation.resume(returning: taken)
        // The camera goes with the panel, not before it: tearing it down mid-fade blanks the feed.
        closing?.fadeOut(duration: Theme.Duration.exit) { [weak self] in
            // Unless a preview raised inside the fade already owns the camera.
            guard let self, !presenting else { return }
            session.stop()
        }
    }

    private func place(_ panel: NSPanel) {
        guard let visible = NSScreen.underCursor?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift))
    }

    /// Optical centering, the same lift a dialog takes.
    private static let centerLift: CGFloat = 0.08

    // MARK: - NSWindowDelegate

    /// Click-away drops the join rather than leaving a camera running behind another window.
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        finish(false)
    }
}
