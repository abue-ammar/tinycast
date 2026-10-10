import AppKit
import SwiftUI

struct FormTextInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder = ""
    let label: String
    var moveFocus: (Bool) -> Void

    @Environment(\.metrics) private var metrics
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.cell = InputCell(textCell: "")
        view.isBordered = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.clipsToBounds = true
        view.usesSingleLineMode = true
        view.cell?.isScrollable = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.onFocus = { [weak coordinator = context.coordinator] in
            guard let coordinator, !coordinator.input.focused else { return }
            coordinator.input.focused = true
        }
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        context.coordinator.input = self
        let font = metrics.typography.textNSFont(.body)
        if view.font != font { view.font = font }
        let color = NSColor(Theme.Colors.textPrimary)
        if view.textColor != color { view.textColor = color }
        let placeholder = NSAttributedString(
            string: placeholder,
            attributes: [.font: font, .foregroundColor: NSColor(Theme.Colors.textTertiary)])
        if view.placeholderAttributedString != placeholder {
            view.placeholderAttributedString = placeholder
        }
        (view.cell as? InputCell)?.inset = metrics.spacing.xl
        if view.isEditable != isEnabled { view.isEditable = isEnabled }
        if view.isSelectable != isEnabled { view.isSelectable = isEnabled }
        if view.stringValue != text { view.stringValue = text }
        view.setAccessibilityLabel(label)
        view.wantsFocus = focused
        view.updateFocus()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InputView, context: Context) -> CGSize? {
        proposal.width.map { CGSize(width: $0, height: metrics.size.dialogButtonHeight) }
    }

    final class InputView: NSTextField {
        var wantsFocus = false
        var onFocus: (() -> Void)?

        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

        override func becomeFirstResponder() -> Bool {
            guard super.becomeFirstResponder() else { return false }
            onFocus?()
            return true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateFocus()
        }

        func updateFocus() {
            if wantsFocus, isEditable, currentEditor() == nil, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
        }
    }

    final class InputCell: NSTextFieldCell {
        var inset: CGFloat = 0

        override func drawInterior(withFrame rect: NSRect, in controlView: NSView) {
            super.drawInterior(withFrame: contentRect(forBounds: rect), in: controlView)
        }

        override func edit(
            withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
            delegate: Any?, event: NSEvent?
        ) {
            super.edit(
                withFrame: contentRect(forBounds: rect), in: controlView, editor: textObj,
                delegate: delegate, event: event)
        }

        override func select(
            withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
            delegate: Any?, start selStart: Int, length selLength: Int
        ) {
            super.select(
                withFrame: contentRect(forBounds: rect), in: controlView, editor: textObj,
                delegate: delegate, start: selStart, length: selLength)
        }

        func contentRect(forBounds rect: NSRect) -> NSRect {
            guard let font else { return super.drawingRect(forBounds: rect) }
            let height = ceil(font.ascender - font.descender + font.leading)
            // AppKit rounds its baseline before laying out the field editor.
            let content = NSRect(
                x: rect.minX + inset,
                y: rect.minY + (rect.height + font.capHeight) / 2 - font.ascender.rounded(),
                width: max(0, rect.width - inset * 2), height: height)
            return controlView?.backingAlignedRect(content, options: .alignAllEdgesNearest) ?? content
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var input: FormTextInput

        init(_ input: FormTextInput) { self.input = input }

        func controlTextDidEndEditing(_ notification: Notification) { input.focused = false }

        func controlTextDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextField else { return }
            input.text = view.stringValue
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                input.moveFocus(false)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                input.moveFocus(true)
                return true
            default:
                return false
            }
        }
    }
}
