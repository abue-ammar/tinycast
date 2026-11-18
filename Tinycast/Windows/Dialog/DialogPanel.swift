import AppKit
import Carbon.HIToolbox

/// One dialog's panel; keys go through `sendEvent`, so Esc/↵ need no focused subview.
final class DialogPanel: NSPanel, AnimatedPanel {
    /// What the panel saw, not what it means: how far a step moves is the caller's business.
    enum Key {
        case cancel
        case confirm
        case increment
        case decrement
        case tab
        case backtab
    }

    var onKey: ((Key) -> Void)?
    /// Arrows are a control's keys, not the panel's; a text field needs them for its caret.
    var handlesArrowKeys = false
    var handlesTabKey = false
    var acceptsLineBreaks = false

    init(content: NSView, cornerRadius: CGFloat) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .dialog
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        followMotion()
        isReleasedWhenClosed = false
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
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
        case kVK_Return where returnBelongsToText(event):
            super.sendEvent(event)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onKey(.confirm)
        case kVK_Tab where handlesTabKey && !hasMarkedText:
            onKey(event.modifierFlags.contains(.shift) ? .backtab : .tab)
        case kVK_LeftArrow where handlesArrowKeys,
            kVK_DownArrow where handlesArrowKeys:
            onKey(.decrement)
        case kVK_RightArrow where handlesArrowKeys,
            kVK_UpArrow where handlesArrowKeys:
            onKey(.increment)
        default:
            super.sendEvent(event)
        }
    }

    /// An input method commits its marked text on ↵, so that press is never a confirm.
    private func returnBelongsToText(_ event: NSEvent) -> Bool {
        hasMarkedText || (acceptsLineBreaks && !event.modifierFlags.contains(.command))
    }

    private var hasMarkedText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func focusFirstTextField() {
        // SwiftUI builds its text fields on first layout, which may not have run by turning key.
        contentView?.layoutSubtreeIfNeeded()
        guard let field = contentView.flatMap(Self.firstTextField(in:)) else { return }
        makeFirstResponder(field)
    }

    private static func firstTextField(in view: NSView) -> NSView? {
        if let field = view as? NSTextField, field.isEditable { return field }
        if let text = view as? NSTextView, text.isEditable { return text }
        return view.subviews.lazy.compactMap(firstTextField(in:)).first
    }
}
