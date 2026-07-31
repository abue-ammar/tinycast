import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ModalAction {
    enum Role {
        case normal
        case destructive
        case cancel
    }

    let title: String
    var role: Role = .normal
}

/// A dialog's visual tone, which drives its leading glyph's tint, default icon, and the pill's
/// status dot. `.warning` is a confirmation asking before something happens; `.error` is a report
/// that something already went wrong — both share the same red tint (severity reads the same either
/// way), so the shape of the default icon is what tells them apart. `.custom` is the template for a
/// one-off dialog that doesn't fit the other four: it carries its own tint and, via
/// `ModalRequest.symbol`, its own icon, rather than deriving either.
enum ModalKind: Sendable {
    case info
    case success
    case warning
    case error
    case custom(Color)

    var tint: Color {
        switch self {
        case .info: return .secondary
        case .success: return Theme.Colors.success
        case .warning: return Theme.Colors.destructive
        case .error: return Theme.Colors.destructive
        case .custom(let color): return color
        }
    }

    var defaultSymbol: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .custom: return "questionmark.circle"
        }
    }
}

struct ModalRequest {
    let title: String
    var message: String?
    /// Falls back to `kind.defaultSymbol` when unset; a `.custom` kind should always set this explicitly.
    var symbol: String? = nil
    var kind: ModalKind = .warning
    var actions: [ModalAction]
    /// The button ↵ fires, normally the primary/confirm action.
    var defaultIndex: Int
    /// Resolved when the modal goes away without a choice: Esc, or losing key status to a click elsewhere.
    var cancelIndex: Int
    var showsVolumeSlider = false
}

/// Borderless panel hosting one Tinycast modal or HUD. Keys are intercepted in `sendEvent` rather than SwiftUI's `onKeyPress` so Esc/↵ work without depending on anything inside the dialog holding focus.
final class ModalPanel: NSPanel {
    enum Key {
        case cancel
        case confirm
        case adjust(Double)
    }

    var onKey: ((Key) -> Void)?
    private let acceptsKey: Bool

    init(content: NSView, acceptsKey: Bool) {
        self.acceptsKey = acceptsKey
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the palette's `.floating`, so a confirmation is never buried under the window that triggered it.
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onKey else {
            super.sendEvent(event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onKey(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onKey(.confirm)
        case kVK_LeftArrow, kVK_DownArrow:
            onKey(.adjust(-Self.arrowStep))
        case kVK_RightArrow, kVK_UpArrow:
            onKey(.adjust(Self.arrowStep))
        default:
            super.sendEvent(event)
        }
    }

    /// Matches the volume commands' own 1/16 step, so arrowing the slider lands on the same values Turn Volume Up/Down produce.
    private static let arrowStep = 1.0 / 16

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

/// Tinycast's own dialogs. The app deliberately never shows an `NSAlert`: confirmations, failures and the volume control all render in the palette's design system.
@MainActor
final class ModalWindowController: NSObject, NSWindowDelegate {
    /// Shared by the Set Volume slider and the HUD's read-only bar; published so a repeated volume command refreshes a HUD that is already on screen instead of rebuilding it.
    final class VolumeState: ObservableObject {
        @Published var level: Double
        @Published var muted: Bool

        init(level: Double, muted: Bool = false) {
            self.level = level
            self.muted = muted
        }
    }

    private var panel: ModalPanel?
    private var continuation: CheckedContinuation<Int, Never>?
    private var volume = VolumeState(level: 0)
    private var hud: ModalPanel?
    /// The volume HUD's own level/muted, distinct from `volume` above: that one is the live Set Volume slider's binding, this is a snapshot for the read-only bar.
    private let hudVolume = VolumeState(level: 0)
    private var hudDismissal: Task<Void, Never>?

    /// `kind` defaults to the usual `.warning`/`.info` split by `destructive`, but a caller can pass
    /// `.error` instead to make a particularly severe confirmation (data loss, ending the session)
    /// read as more alarming than a routine one, without that dialog claiming something already went wrong.
    func confirm(
        title: String, message: String?, confirmTitle: String, destructive: Bool,
        kind: ModalKind? = nil
    ) async -> Bool {
        let request = ModalRequest(
            title: title, message: message, kind: kind ?? (destructive ? .warning : .info),
            actions: [
                ModalAction(title: confirmTitle, role: destructive ? .destructive : .normal),
                ModalAction(title: "Cancel", role: .cancel),
            ],
            defaultIndex: 0, cancelIndex: 1)
        return await present(request) == 0
    }

    func notice(title: String, message: String, symbol: String? = nil, kind: ModalKind = .info)
        async
    {
        let request = ModalRequest(
            title: title, message: message, symbol: symbol, kind: kind,
            actions: [ModalAction(title: "OK", role: .cancel)], defaultIndex: 0, cancelIndex: 0)
        _ = await present(request)
    }

    /// A failure report: something already went wrong, as opposed to `confirm`'s "about to happen".
    /// Returns true when the user asked to be taken to the relevant settings.
    func report(title: String, message: String, settingsTitle: String?) async -> Bool {
        var actions = [ModalAction(title: "OK", role: .cancel)]
        if let settingsTitle { actions.append(ModalAction(title: settingsTitle)) }
        // ↵ lands on the settings action when there is one to take, not on the OK dismissal.
        let request = ModalRequest(
            title: title, message: message, kind: .error,
            actions: actions, defaultIndex: actions.count - 1, cancelIndex: 0)
        return await present(request) == 1
    }

    func pickVolume(current: Float32) async -> Float32? {
        volume = VolumeState(level: Double(current))
        let request = ModalRequest(
            title: "Set Volume", message: "Choose the output volume.", symbol: "speaker.wave.2",
            kind: .info,
            actions: [
                ModalAction(title: "Set Volume"),
                ModalAction(title: "Cancel", role: .cancel),
            ],
            defaultIndex: 0, cancelIndex: 1, showsVolumeSlider: true)
        guard await present(request) == 0 else { return nil }
        return Float32(volume.level)
    }

    /// Feedback for the volume and mute commands, which otherwise change the output with nothing on screen, since macOS only draws its own HUD for real media keys. Success/info toasts for other commands go through `HUDWindowController`'s pill instead, since this box's whole point is showing the level.
    func showVolumeHUD(level: Float32, muted: Bool) {
        hudVolume.level = Double(level)
        hudVolume.muted = muted
        if hud == nil {
            let view = hostingView(
                VolumeHUDView(state: hudVolume), width: Theme.Size.hudWidth,
                minHeight: Theme.Size.hudHeight)
            let panel = ModalPanel(content: view, acceptsKey: false)
            place(panel, anchor: .hud)
            panel.orderFrontRegardless()
            hud = panel
        }
        hudDismissal?.cancel()
        hudDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Duration.hud))
            guard !Task.isCancelled else { return }
            self?.dismissHUD()
        }
    }

    private func dismissHUD() {
        hud?.orderOut(nil)
        hud = nil
        hudDismissal = nil
    }

    private func present(_ request: ModalRequest) async -> Int {
        // Carbon hotkeys keep firing while a dialog is up; a held shortcut must not stack a second one, so the extra request resolves as a dismissal.
        guard panel == nil else { return request.cancelIndex }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let content = hostingView(
                TinycastModalView(
                    request: request, volume: volume,
                    onChoose: { [weak self] index in self?.finish(index) }
                ),
                width: Theme.Size.modalWidth, minHeight: 0)
            let panel = ModalPanel(content: content, acceptsKey: true)
            panel.delegate = self
            panel.onKey = { [weak self] key in
                guard let self else { return }
                switch key {
                case .cancel:
                    finish(request.cancelIndex)
                case .confirm:
                    finish(request.defaultIndex)
                case .adjust(let delta):
                    guard request.showsVolumeSlider else { return }
                    volume.level = min(max(volume.level + delta, 0), 1)
                }
            }
            self.panel = panel
            place(panel, anchor: .center)
            // Non-activating like the palette: the dialog takes key focus for its own keys without pulling app focus away from whatever the user was in.
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    private func finish(_ index: Int) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        continuation.resume(returning: index)
    }

    private func hostingView(_ view: some View, width: CGFloat, minHeight: CGFloat) -> NSView {
        let hosting = NSHostingView(rootView: AnyView(view))
        // Measure at the fixed width first: the message wraps, so the height is only knowable once the width is pinned.
        hosting.setFrameSize(NSSize(width: width, height: minHeight))
        let fitted = hosting.fittingSize
        hosting.setFrameSize(NSSize(width: width, height: max(fitted.height, minHeight)))
        return hosting
    }

    private enum Anchor {
        case center
        case hud
    }

    private func place(_ panel: NSPanel, anchor: Anchor) {
        guard let screen = cursorScreen() else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin: NSPoint
        switch anchor {
        case .center:
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift)
        case .hud:
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + visible.height * Self.hudBottomFraction)
        }
        panel.setFrameOrigin(origin)
    }

    /// Optical centering: a dialog placed on the exact vertical middle reads low, the same reason the palette sits above center.
    private static let centerLift: CGFloat = 0.08
    private static let hudBottomFraction: CGFloat = 0.12

    /// The display the user is working on. `NSScreen.main` is the key window's screen, which an accessory app driving non-activating panels never reliably has.
    private func cursorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        // NSMouseInRect, not `contains`: a pointer on a display's topmost row otherwise resolves to the display stacked above it.
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: - NSWindowDelegate

    /// Click-away resolves as a dismissal rather than leaving an orphaned dialog behind.
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        panel.onKey?(.cancel)
    }
}
