import AppKit
import SwiftUI

@MainActor
final class NotesWindowController: NSObject {
    enum HeightBehavior: Equatable {
        case fitContent
        case trackContent
        case preserve
    }

    private static let frameAutosaveName = "Tinycast Floating Note"

    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private weak var editor: NoteTextView?
    private var previousApp: NSRunningApplication?
    private weak var previousOwnWindow: NSWindow?
    private var editorHeight: CGFloat = 0
    private var editorGrowthPadding: CGFloat = 0
    private var hasPositionedPanel = false

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(
        initialEditorHeight: CGFloat,
        focusEditor: Bool,
        heightBehavior: HeightBehavior = .fitContent
    ) {
        let wasVisible = panel?.isVisible == true
        if !wasVisible { captureFocusTarget() }
        editorHeight = initialEditorHeight
        if heightBehavior == .fitContent { editorGrowthPadding = 0 }
        let panel = ensurePanel()
        position(panel, heightBehavior: heightBehavior)
        if heightBehavior == .fitContent {
            editorGrowthPadding = NoteWindowLayout.editorGrowthPadding(
                initialEditorContentHeight: initialEditorHeight,
                initialPanelHeight: panel.frame.height,
                metrics: Self.metrics)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if focusEditor { self.focusEditor(in: panel) }
    }

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        guard restoreFocus else { return }
        if let previousOwnWindow, previousOwnWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            previousOwnWindow.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    func updateEditorHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        editorHeight = height
        guard let panel else { return }
        position(panel, heightBehavior: .trackContent)
    }

    func editorReady(_ textView: NoteTextView) {
        editor = textView
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    func focusEditor() {
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    func saveFrame() {
        guard let panel else { return }
        position(panel, heightBehavior: .preserve)
        panel.saveFrame(usingName: Self.frameAutosaveName)
    }

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let root = NotesView().environment(coordinator)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NotesPanel(content: hosting)
        panel.onHide = { [weak coordinator] in coordinator?.hide() }
        panel.onEscape = { [weak coordinator] in coordinator?.handleEscape() }
        panel.onCreate = { [weak coordinator] in coordinator?.createNote() }
        panel.onSearch = { [weak coordinator] in coordinator?.searchNotes() }
        panel.onDelete = { [weak coordinator] in coordinator?.handleDeleteShortcut() ?? false }
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        self.panel = panel
        return panel
    }

    private func position(
        _ panel: NotesPanel,
        heightBehavior: HeightBehavior = .fitContent
    ) {
        let restored = !hasPositionedPanel && panel.setFrameUsingName(Self.frameAutosaveName)
        let visibleFrame = panel.screen?.visibleFrame
            ?? screenContaining(panel.frame)?.visibleFrame
            ?? NSScreen.underCursor?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }
        let constrainedVisibleFrame = NoteWindowLayout.constrainedVisibleFrame(
            visibleFrame,
            metrics: Self.metrics)
        let height: CGFloat = switch heightBehavior {
        case .fitContent:
            NoteWindowLayout.panelHeight(
                editorContentHeight: editorHeight,
                visibleScreenHeight: visibleFrame.height,
                metrics: Self.metrics)
        case .trackContent:
            NoteWindowLayout.contentTrackingPanelHeight(
                editorContentHeight: editorHeight,
                editorGrowthPadding: editorGrowthPadding,
                visibleScreenHeight: visibleFrame.height,
                metrics: Self.metrics)
        case .preserve:
            NoteWindowLayout.preservedPanelHeight(
                panel.frame.height,
                visibleScreenHeight: visibleFrame.height,
                metrics: Self.metrics)
        }
        let frame = if restored || hasPositionedPanel {
            NoteWindowLayout.resizedFrame(
                currentFrame: panel.frame,
                height: height,
                visibleFrame: constrainedVisibleFrame,
                width: Theme.Size.noteWidth)
        } else {
            NoteWindowLayout.initialFrame(
                visibleFrame: constrainedVisibleFrame,
                height: height,
                width: Theme.Size.noteWidth,
                centerLiftFraction: Theme.Size.noteCenterLiftFraction)
        }
        if panel.frame != frame {
            panel.setFrame(frame, display: panel.isVisible, animate: false)
        }
        hasPositionedPanel = true
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func captureFocusTarget() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApp = nil
            if let keyWindow = NSApp.keyWindow, keyWindow !== panel {
                previousOwnWindow = keyWindow
            }
        } else {
            previousApp = frontmost
            previousOwnWindow = nil
        }
    }

    private func focusEditor(in panel: NotesPanel) {
        guard let editor else { return }
        panel.makeFirstResponder(editor)
        Task { @MainActor [weak panel, weak editor] in
            await Task.yield()
            guard let panel, panel.isVisible, let editor else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(editor)
        }
    }

    private static let metrics = NoteWindowLayout.Metrics(
        minimumHeight: Theme.Size.noteMinimumHeight,
        maximumHeight: Theme.Size.noteMaximumHeight,
        screenMargin: Theme.Size.noteScreenMargin,
        fixedContentHeight: Theme.Size.noteHeaderHeight)
}
