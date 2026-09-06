import AppKit
import SwiftUI

/// Identifies the editor to present; nil is "new", and the UUID keeps two opens distinct.
struct WindowLayoutEditRequest: Identifiable {
    let id = UUID()
    var layout: WindowLayout?
    /// Set by capture, so the sheet says what it is showing.
    var isCapture = false
}

/// Add / edit sheet for one layout, presented from the Window Management pane.
struct WindowLayoutEditorSheet: View {
    let request: WindowLayoutEditRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var draft: WindowLayoutDraft
    @State private var screens: [WindowLayoutScreen]
    @State private var errorMessage: String?

    init(request: WindowLayoutEditRequest) {
        self.request = request
        let connected = Self.connectedScreens()
        _screens = State(initialValue: connected)
        _draft = State(
            initialValue: WindowLayoutDraft(
                layout: request.layout, isCapture: request.isCapture,
                displays: connected.map(\.display)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(title)
                .font(.title2.weight(.bold))

            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                WindowLayoutPreview(draft: draft, screens: screens, gap: previewGap)
                WindowLayoutInspector(draft: draft, displays: screens.map(\.display))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            footer
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.layoutEditorSheet)
        .task {
            // A display can be unplugged while the sheet is open; the canvas must not draw
            // against geometry that is gone.
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification)
            {
                screens = Self.connectedScreens()
            }
        }
    }

    private static func connectedScreens() -> [WindowLayoutScreen] {
        AXScreens.layoutScreens(geometry: AXGeometry(screens: NSScreen.screens))
    }

    private var title: String {
        if request.isCapture { return "Capture Window Layout" }
        return request.layout == nil ? "New Window Layout" : "Edit Window Layout"
    }

    private var previewGap: CGFloat {
        draft.usesPreferredGap ? CGFloat(settings.windowGap) : 0
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(action: save) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Save")
                    HStack(spacing: Theme.Spacing.xxs) {
                        KeyCapChip(text: "⌘", scale: .compact)
                        KeyCapChip(text: "↵", scale: .compact)
                    }
                }
            }
            // Not `.defaultAction`: plain ↵ belongs to whichever field has focus.
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!draft.canSave)
        }
    }

    private func save() {
        guard draft.canSave else { return }
        let value = draft.layout()
        do {
            if draft.existingID == nil || core.windowLayouts.layout(id: value.id) == nil {
                try core.windowLayoutCoordinator.addWindowLayout(value)
            } else {
                try core.windowLayoutCoordinator.updateWindowLayout(value)
            }
            dismiss()
        } catch {
            errorMessage = error.errorDescription
        }
    }
}
