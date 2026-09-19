import AppKit
import SwiftUI

/// One stack per Settings window: bindings own presentation state, this owns only AppKit edges.
@MainActor
final class SettingsEditorPresenter: NSObject {
    struct DismissAction {
        private let action: () -> Void

        init(_ action: @escaping () -> Void = {}) {
            self.action = action
        }

        func callAsFunction() {
            action()
        }
    }

    fileprivate struct BooleanPanelModifier<PanelContent: View>: ViewModifier {
        @Environment(\.settingsEditorPresenter) private var presenter
        @Binding var isPresented: Bool
        let panelContent: () -> PanelContent
        @State private var presentationID = UUID()

        func body(content: Content) -> some View {
            content
                .onChange(of: isPresented, initial: true) { _, presented in
                    guard let presenter else { return }
                    if presented {
                        let binding = $isPresented
                        presenter.present(
                            id: presentationID,
                            onDismiss: {
                                binding.wrappedValue = false
                            }
                        ) {
                            panelContent()
                        }
                    } else {
                        presenter.dismiss(id: presentationID, notifying: false)
                    }
                }
                .onDisappear {
                    presenter?.dismiss(id: presentationID)
                }
        }
    }

    fileprivate struct ItemPanelModifier<Item: Identifiable, PanelContent: View>: ViewModifier {
        @Environment(\.settingsEditorPresenter) private var presenter
        @Binding var item: Item?
        let panelContent: (Item) -> PanelContent
        @State private var presentationID = UUID()

        func body(content: Content) -> some View {
            content
                .onChange(of: item?.id, initial: true) { _, _ in
                    guard let presenter else { return }
                    presenter.dismiss(id: presentationID, notifying: false)
                    guard let presentedItem = item else { return }
                    let binding = $item
                    let itemID = presentedItem.id
                    presenter.present(
                        id: presentationID,
                        onDismiss: {
                            guard binding.wrappedValue?.id == itemID else { return }
                            binding.wrappedValue = nil
                        }
                    ) {
                        panelContent(presentedItem)
                    }
                }
                .onDisappear {
                    presenter?.dismiss(id: presentationID)
                }
        }
    }

    private struct Pending {
        let id: UUID
        let content: AnyView
        let onDismiss: () -> Void
    }

    private final class Presentation {
        let id: UUID
        weak var parent: NSWindow?
        let panel: Panel
        let blocker: BlockingPanel
        let onDismiss: () -> Void

        init(
            id: UUID, parent: NSWindow, panel: Panel,
            blocker: BlockingPanel, onDismiss: @escaping () -> Void
        ) {
            self.id = id
            self.parent = parent
            self.panel = panel
            self.blocker = blocker
            self.onDismiss = onDismiss
        }
    }

    private final class Panel: NSPanel {
        var cancelHandler: (() -> Void)?

        init(content: NSView, cornerRadius: CGFloat) {
            super.init(
                contentRect: NSRect(origin: .zero, size: content.frame.size),
                styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
            isFloatingPanel = true
            becomesKeyOnlyIfNeeded = false
            hidesOnDeactivate = false
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            animationBehavior = .none
            isMovableByWindowBackground = false
            isReleasedWhenClosed = false
            content.wantsLayer = true
            content.layer?.cornerCurve = .continuous
            content.layer?.cornerRadius = cornerRadius
            content.layer?.masksToBounds = true
            contentView = content
        }

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        /// The fallback: a panel whose content declares `.cancelAction` handles Escape itself.
        override func cancelOperation(_ sender: Any?) {
            cancelHandler?()
        }

        func animateEntrance(offset: CGFloat, startingOpacity: CGFloat, duration: TimeInterval) {
            guard let layer = contentView?.layer else { return }

            let movement = CABasicAnimation(keyPath: "transform.translation.y")
            movement.fromValue = -offset
            movement.toValue = 0
            movement.duration = duration

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = startingOpacity
            opacity.toValue = 1
            opacity.duration = duration

            let entrance = CAAnimationGroup()
            entrance.animations = [movement, opacity]
            entrance.duration = duration
            entrance.timingFunction = CAMediaTimingFunction(name: .easeOut)

            layer.add(entrance, forKey: "settingsEditorEntrance")
            alphaValue = 1
        }

        func focusFirstControl() {
            makeKey()
            selectNextKeyView(nil)
        }
    }

    private final class BlockingPanel: NSPanel {
        private weak var target: NSWindow?

        init(target: NSWindow, cornerRadius: CGFloat) {
            self.target = target
            super.init(
                contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            animationBehavior = .none
            isReleasedWhenClosed = false
            alphaValue = 0
            contentView = NSHostingView(
                rootView: Theme.Colors.dialogDimming
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .ignoresSafeArea())
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        override func sendEvent(_ event: NSEvent) {
            guard event.type == .leftMouseDown || event.type == .rightMouseDown else {
                super.sendEvent(event)
                return
            }
            target?.makeKeyAndOrderFront(nil)
        }
    }

    private unowned let core: AppCore
    private let navigation: SettingsNavigationState
    private weak var parentWindow: NSWindow?
    private var pending: [Pending] = []
    private var presentations: [Presentation] = []

    init(core: AppCore, navigation: SettingsNavigationState) {
        self.core = core
        self.navigation = navigation
        super.init()
    }

    func attach(to window: NSWindow?) {
        guard let window, parentWindow !== window else { return }
        if let parentWindow {
            NotificationCenter.default.removeObserver(self, name: nil, object: parentWindow)
        }
        parentWindow = window
        NotificationCenter.default.addObserver(
            self, selector: #selector(parentWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window)
        observeResize(of: window)
        flushPending()
    }

    @objc private func parentWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === parentWindow else { return }
        dismissAll()
        NotificationCenter.default.removeObserver(self, name: nil, object: parentWindow)
        parentWindow = nil
    }

    func present<Content: View>(
        id: UUID, onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) {
        guard !contains(id) else { return }
        pending.append(Pending(id: id, content: AnyView(content()), onDismiss: onDismiss))
        flushPending()
    }

    func dismiss(id: UUID, notifying: Bool = true) {
        if let pendingIndex = pending.firstIndex(where: { $0.id == id }) {
            let request = pending.remove(at: pendingIndex)
            if notifying { request.onDismiss() }
            return
        }
        guard let index = presentations.firstIndex(where: { $0.id == id }) else { return }
        while presentations.indices.contains(index) {
            let shouldNotify = presentations.last?.id == id ? notifying : true
            dismissLast(notifying: shouldNotify)
        }
    }

    func dismissAll() {
        let pendingRequests = pending
        pending.removeAll()
        pendingRequests.forEach { $0.onDismiss() }
        while !presentations.isEmpty { dismissLast(notifying: true) }
    }

    private func contains(_ id: UUID) -> Bool {
        pending.contains { $0.id == id } || presentations.contains { $0.id == id }
    }

    private func flushPending() {
        guard parentWindow != nil else { return }
        while !pending.isEmpty { show(pending.removeFirst()) }
    }

    private func show(_ request: Pending) {
        guard let parent = presentations.last?.panel ?? parentWindow else { return }
        let dismiss = DismissAction { [weak self] in
            self?.dismiss(id: request.id)
        }
        let root = request.content
            .settingsEnvironment(core: core, navigation: navigation, editorPresenter: self)
            .environment(\.settingsEditorDismiss, dismiss)
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.setFrameSize(NSSize(width: 1, height: 1))
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        hosting.setFrameSize(
            NSSize(width: max(1, fitting.width), height: max(1, fitting.height)))

        let panel = Panel(content: hosting, cornerRadius: Theme.Radius.panel)
        panel.cancelHandler = { [weak self] in self?.dismiss(id: request.id) }
        let blocker = BlockingPanel(
            target: panel, cornerRadius: blockerCornerRadius(for: parent))
        let presentation = Presentation(
            id: request.id, parent: parent, panel: panel, blocker: blocker,
            onDismiss: request.onDismiss)
        presentations.append(presentation)
        // Its own resize too: the content sizes the panel, so a growing form must re-centre it.
        observeResize(of: panel)
        layout(presentation)
        panel.alphaValue = 0
        parent.addChildWindow(blocker, ordered: .above)
        parent.addChildWindow(panel, ordered: .above)
        blocker.fadeIn(duration: Theme.Duration.dialogEnter) { blocker.orderFront(nil) }
        panel.makeKeyAndOrderFront(nil)
        prepareEntrance(panel: panel)
    }

    private func prepareEntrance(panel: Panel) {
        Task { @MainActor [weak self, weak panel] in
            await Task.yield()
            guard let self, let panel,
                self.presentations.contains(where: { $0.panel === panel })
            else { return }
            panel.focusFirstControl()
            await Task.yield()
            guard self.presentations.contains(where: { $0.panel === panel }) else { return }
            animateEntrance(panel: panel)
        }
    }

    private func animateEntrance(panel: Panel) {
        panel.animateEntrance(
            offset: Theme.DialogMotion.offset,
            startingOpacity: Theme.DialogMotion.initialOpacity,
            duration: Theme.Duration.dialogEnter)
        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(Theme.Duration.dialogEnter))
            guard let self, let panel,
                self.presentations.contains(where: { $0.panel === panel })
            else { return }
            panel.animationBehavior = .utilityWindow
        }
    }

    private func observeResize(of window: NSWindow) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(hostDidResize(_:)),
            name: NSWindow.didResizeNotification, object: window)
    }

    /// Outermost first, so a nested panel centres on a parent that has already settled.
    @objc private func hostDidResize(_ notification: Notification) {
        presentations.forEach(layout)
    }

    private func layout(_ presentation: Presentation) {
        guard let parent = presentation.parent else { return }
        let parentContent = parent.convertToScreen(parent.contentLayoutRect)
        presentation.blocker.setFrame(parent.frame, display: false)
        let panelSize = presentation.panel.frame.size
        presentation.panel.setFrameOrigin(
            NSPoint(
                x: parentContent.midX - panelSize.width / 2,
                y: parentContent.midY - panelSize.height / 2))
    }

    private func blockerCornerRadius(for parent: NSWindow) -> CGFloat {
        let radius = parent.contentView?.layer?.cornerRadius ?? 0
        return radius > 0 ? radius : Theme.Radius.row
    }

    private func dismissLast(notifying: Bool) {
        let presentation = presentations.removeLast()
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResizeNotification, object: presentation.panel)
        if let parent = presentation.parent {
            parent.removeChildWindow(presentation.panel)
            presentation.blocker.fadeOut(duration: Theme.Duration.dialogExit) {
                parent.removeChildWindow(presentation.blocker)
            }
        }
        presentation.panel.orderOut(nil)
        presentation.panel.contentView = nil
        if notifying { presentation.onDismiss() }
        if let panel = presentations.last?.panel {
            panel.makeKeyAndOrderFront(nil)
            panel.focusFirstControl()
        } else {
            parentWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

extension EnvironmentValues {
    @Entry var settingsEditorDismiss = SettingsEditorPresenter.DismissAction()
    @Entry var settingsEditorPresenter: SettingsEditorPresenter?
}

extension View {
    /// Presents editor content in Tinycast's activating child panel, not an opaque macOS sheet.
    func settingsEditorPanel<PanelContent: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> PanelContent
    ) -> some View {
        modifier(
            SettingsEditorPresenter.BooleanPanelModifier(
                isPresented: isPresented, panelContent: content))
    }

    /// The item-driven form used by editors whose initial state is captured when the panel opens.
    func settingsEditorPanel<Item: Identifiable, PanelContent: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> PanelContent
    ) -> some View {
        modifier(SettingsEditorPresenter.ItemPanelModifier(item: item, panelContent: content))
    }

    func settingsEnvironment(
        core: AppCore, navigation: SettingsNavigationState,
        editorPresenter: SettingsEditorPresenter
    ) -> some View {
        environment(\.settingsEditorPresenter, editorPresenter)
            .environment(navigation)
            .environment(core)
            .environment(core.settings)
            .environment(core.appIndex)
            .environment(core.hotKeys)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.fallbacks)
            .environment(core.customCommands)
            .environment(core.snippetsStore)
            .environment(core.quicklinks)
            .environment(core.windowLayouts)
            .environment(core.customWindowSizes)
            .environment(core.customWindowSizeCoordinator)
            .environment(core.calendarStore)
            .environment(core.aiSettings)
            .environment(core.mcpSettings)
            .environment(core.mcpCoordinator)
            .environment(core.quickActionSettings)
            .environment(core.customQuickActions)
            .environment(core.chatGPTSubscription)
            .environment(core.installedAI)
            .scrollContentBackground(.hidden)
    }
}
