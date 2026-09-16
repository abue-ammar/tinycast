import AppKit
import SwiftUI

/// Identifies the editor to present; nil is "new", and the UUID keeps two opens distinct.
struct CustomWindowSizeEditRequest: Identifiable {
    let id = UUID()
    var size: CustomWindowSize?
}

/// Add / edit sheet for one custom size, presented from the Window Management pane.
struct CustomWindowSizeEditorSheet: View {
    private let isNew: Bool
    /// What a unit switch converts against; a run measures the window's own display.
    private let reference: CGSize

    @Environment(\.dismiss) private var dismiss
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
            Text(isNew ? "New Custom Size" : "Edit Custom Size")
                .font(.title2.weight(.bold))

            Text("Resizes the window you were last in, on the display it is already on.")
                .foregroundStyle(.secondary)

            field("Name") {
                TextField("Wide Center", text: $size.name)
                    .textFieldStyle(.roundedBorder)
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

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
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
