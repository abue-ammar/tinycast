import AppKit

@MainActor
final class NoteTaskOverlayController: NSObject {
    private var buttons: [NSButton] = []
    private weak var textView: NSTextView?
    private weak var observedClipView: NSClipView?
    private var tasks: [NoteDisplayProjection.TaskAnchor] = []
    private var epoch = 0
    private var onToggle: ((NSRange, Int) -> Void)?

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(
        _ tasks: [NoteDisplayProjection.TaskAnchor],
        epoch: Int,
        in textView: NSTextView,
        onToggle: @escaping (NSRange, Int) -> Void
    ) {
        self.tasks = tasks
        self.epoch = epoch
        self.textView = textView
        self.onToggle = onToggle
        observeScrolling(in: textView)
        refresh()
    }

    private func refresh() {
        guard let textView, let onToggle else { return }
        while buttons.count < tasks.count {
            let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = true
            textView.addSubview(button)
            buttons.append(button)
        }
        for (index, button) in buttons.enumerated() {
            guard index < tasks.count else {
                button.isHidden = true
                continue
            }
            let task = tasks[index]
            guard let frame = frame(for: task.displayRange, in: textView) else {
                button.isHidden = true
                continue
            }
            button.isHidden = false
            button.state = task.checked ? .on : .off
            button.setAccessibilityLabel(task.label)
            button.setAccessibilityValue(task.checked ? "Checked" : "Unchecked")
            button.frame = NSRect(
                x: frame.minX - 1,
                y: frame.midY - 8,
                width: max(16, frame.width + 2),
                height: 16)
            button.target = CallbackTarget.install(on: button) { [weak self] in
                guard let self else { return }
                onToggle(task.sourceRange, self.epoch)
            }
            button.action = #selector(CallbackTarget.invoke)
        }
    }

    private func observeScrolling(in textView: NSTextView) {
        guard let clipView = textView.enclosingScrollView?.contentView,
            clipView !== observedClipView
        else { return }
        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedClipView)
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: clipView)
    }

    @objc private func scrollBoundsChanged() {
        refresh()
    }

    private func frame(for range: NSRange, in textView: NSTextView) -> CGRect? {
        guard let manager = textView.textLayoutManager,
            let contentManager = manager.textContentManager,
            let textRange = textRange(range, contentManager: contentManager)
        else { return nil }
        manager.ensureLayout(for: textRange)
        var result: CGRect?
        manager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: [.rangeNotRequired, .middleFragmentsExcluded]
        ) { _, frame, _, _ in
            result = frame.offsetBy(
                dx: textView.textContainerInset.width,
                dy: textView.textContainerInset.height)
            return false
        }
        return result
    }

    private func textRange(
        _ range: NSRange,
        contentManager: NSTextContentManager
    ) -> NSTextRange? {
        let document = contentManager.documentRange
        guard let start = contentManager.location(document.location, offsetBy: range.location),
            let end = contentManager.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }
}

@MainActor
private final class CallbackTarget: NSObject {
    private static var key: UInt8 = 0
    private let action: () -> Void

    private init(action: @escaping () -> Void) {
        self.action = action
    }

    static func install(on button: NSButton, action: @escaping () -> Void) -> CallbackTarget {
        let target = CallbackTarget(action: action)
        objc_setAssociatedObject(button, &key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return target
    }

    @objc func invoke() {
        action()
    }
}
