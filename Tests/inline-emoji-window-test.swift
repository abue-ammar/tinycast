import AppKit
import Observation
import SwiftUI

@main
@MainActor
struct InlineEmojiWindowTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { await run(app: app) }
        app.run()
    }

    private static func run(app: NSApplication) async {
        var failures = 0
        var checks = 0
        func expect(_ condition: Bool, _ description: String) {
            checks += 1
            if !condition { print("FAIL: \(description)"); failures += 1 }
        }
        guard let screen = NSScreen.screens.first else {
            print("FAIL: an unlocked desktop is required")
            exit(1)
        }
        let settings = AppSettings()
        let coordinator = InlineEmojiCoordinator()
        let controller = InlineEmojiWindowController()
        let entries = (0..<6).map { index in
            EmojiEntry(
                glyph: String(Unicode.Scalar(0x1F600 + index)!), name: "smiling face \(index)",
                category: .smileysAndPeople, supportsSkinTone: false, keywords: "smile")
        }
        let top = screen.frame.maxY
        for size in InterfaceSize.allCases {
            settings.interfaceSize = size
            for count in [0, 1, 6] {
                coordinator.entries = Array(entries.prefix(count))
                var previous: NSWindow?
                for anchor in [
                    CGRect(
                        x: screen.visibleFrame.minX, y: top - screen.visibleFrame.maxY, width: 1, height: 20),
                    CGRect(
                        x: screen.visibleFrame.maxX - 1, y: top - screen.visibleFrame.minY - 20, width: 1,
                        height: 20)
                ] {
                    controller.show(coordinator: coordinator, settings: settings, anchor: anchor)
                    try? await Task.sleep(for: .milliseconds(20))
                    guard let panel = app.windows.first(where: \.isVisible) else {
                        expect(false, "a picker panel is presented")
                        continue
                    }
                    expect(panel.frame.height > 30, "\(size) with \(count) results has visible height")
                    expect(
                        panel.contentView?.frame.size == panel.frame.size, "the hosted picker fills the panel"
                    )
                    expect(
                        panel.frame.width == size.metrics.size.menuWidth, "the interface scale controls width"
                    )
                    expect(screen.visibleFrame.contains(panel.frame), "the panel stays within the screen")
                    expect(!panel.canBecomeKey && !panel.canBecomeMain, "the panel preserves typing focus")
                    expect(
                        coordinator.listener.bounds?.height == panel.frame.height,
                        "click bounds cover the visible panel")
                    if let previous { expect(previous === panel, "query updates reuse the panel") }
                    previous = panel
                }
                weak var hosting = previous?.contentView
                controller.hide()
                try? await Task.sleep(for: .milliseconds(20))
                expect(
                    previous?.isVisible == false && previous?.contentView == nil,
                    "dismissal clears the hosted tree")
                expect(hosting == nil, "dismissal releases the hosting view")
            }
        }
        print("\(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

@MainActor
@Observable
final class AppSettings {
    var interfaceSize = InterfaceSize.standard
    var inlineEmojiSuggestions = InlineEmojiSuggestions.frequentlyUsed
    var emojiSkinTone = EmojiSkinTone.none
}

@MainActor
@Observable
final class InlineEmojiCoordinator {
    var query = "smile"
    var entries: [EmojiEntry] = []
    var selection = 0
    let listener = InlineEmojiListener()

    func select(_ index: Int) { selection = index }
    func insertSelection() {}
}

@MainActor
final class InlineEmojiListener {
    var bounds: CGRect?
    func setPanelBounds(_ bounds: CGRect?) { self.bounds = bounds }
}
