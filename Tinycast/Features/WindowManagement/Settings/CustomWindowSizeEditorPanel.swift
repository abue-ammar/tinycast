import AppKit
import SwiftUI

/// Identifies the editor to present; nil is "new", and the UUID keeps two opens distinct.
struct CustomWindowSizeEditRequest: Identifiable {
    let id = UUID()
    var size: CustomWindowSize?
}

/// Add / edit panel for one custom size, presented from the Window Management pane.
struct CustomWindowSizeEditorPanel: View {
    private let isNew: Bool
    /// What a unit switch converts against; a run measures the window's own display.
    private let reference: CGSize

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(CustomWindowSizeCoordinator.self) private var coordinator
    @State private var size: CustomWindowSize
    @State private var errorMessage: String?

    init(request: CustomWindowSizeEditRequest) {
        isNew = request.size == nil
        reference = NSScreen.main?.visibleFrame.size ?? .zero
        _size = State(initialValue: request.size ?? CustomWindowSize(name: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: isNew ? "New Custom Size" : "Edit Custom Size",
                subtitle: "Resizes the window you were last in, on the display it is already on.")

            field("Name") {
                TextField("Wide Center", text: $size.name)
                    .settingsEditorTextField()
            }

            field("Size") {
                HStack(spacing: Theme.Spacing.lg) {
                    dimensionField(
                        label: "W", name: "Width", dimension: $size.width,
                        available: reference.width)
                    dimensionField(
                        label: "H", name: "Height", dimension: $size.height,
                        available: reference.height)
                }
            }

            field("Position") {
                WindowLayoutPositionGrid(selection: size.anchor) { size.anchor = $0 }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.callout.weight(.medium))
            content()
        }
    }

    private func dimensionField(
        label: String, name: String, dimension: Binding<CustomWindowSize.Dimension>,
        available: CGFloat
    ) -> some View {
        let unit = dimension.wrappedValue.unit
        return HStack(spacing: Theme.Spacing.sm) {
            WindowLayoutNumberField(
                label: label, name: name, suffix: unit.suffix, range: unit.range,
                value: dimension.wrappedValue.value,
                onCommit: { dimension.wrappedValue = .init($0, unit) })
            Picker(
                "\(name) unit",
                selection: Binding(
                    get: { unit },
                    set: {
                        dimension.wrappedValue = dimension.wrappedValue.converted(
                            to: $0, in: available)
                    })
            ) {
                ForEach(CustomWindowSize.Dimension.Unit.allCases, id: \.self) {
                    Text($0.suffix).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.barControl))
            .fixedSize()
        }
    }

    private var canSave: Bool {
        !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        do {
            try coordinator.saveCustomWindowSize(size)
            dismiss()
        } catch {
            errorMessage = error.errorDescription
        }
    }
}
