import SwiftUI

struct WindowManagementSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    @State private var editor: WindowLayoutEditRequest?
    @State private var pendingDeletion: WindowLayout?
    @State private var customSizeEdit: CustomWindowSizeEditRequest?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .windowManagementWindowManagement,
                enableTitle: "Enable window management",
                enableSubtitle: "Moves the last window you used. Needs Accessibility.",
                isEnabled: $settings.windowManagementEnabled,
                showsInLauncher: $settings.windowManagementShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Group {
                options
                WindowLayoutsSection(
                    onEdit: { editor = WindowLayoutEditRequest(layout: $0) },
                    onDelete: { pendingDeletion = $0 })
                RoomsSection()
                FeatureCommandsSection(
                    owner: .windowManagement, anchor: .windowManagementLayoutCommands)
                CustomWindowSizesSection(onEdit: {
                    customSizeEdit = CustomWindowSizeEditRequest(size: $0)
                })
                commands
            }
            .settingsEnabled(settings.windowManagementEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowManagement)
        .settingsEditorPanel(item: $editor) { request in
            WindowLayoutEditorPanel(request: request)
        }
        .onChange(of: core.pendingWindowLayoutEdit?.id, initial: true) { _, _ in
            guard let request = core.pendingWindowLayoutEdit else { return }
            editor = request
            core.pendingWindowLayoutEdit = nil
        }
        .settingsEditorPanel(item: $customSizeEdit) { request in
            CustomWindowSizeEditorPanel(request: request)
        }
        .alert(item: $pendingDeletion) { layout in
            Alert(
                title: Text("Delete \u{201C}\(layout.name)\u{201D}?"),
                message: Text("Its global shortcut and launcher references go with it."),
                primaryButton: .destructive(Text("Delete")) {
                    core.windowLayoutCoordinator.deleteWindowLayout(id: layout.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var options: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.windowCycle) {
                ForEach(WindowCycle.allCases) { cycle in
                    Text(cycle.title).tag(cycle)
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Cycling")
                Text(settings.windowCycle.detail)
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(settings.windowGap) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Gap between windows", value: $settings.windowGap, in: 0...64, step: 2)
                        .labelsHidden()
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Gap between windows")
                Text("Between tiled windows and screen edges.")
            }
        } header: {
            SettingsSectionHeader(.windowManagementOptions)
        }
    }

    /// One section per catalog group, so the sidebar's own grouping carries the headings.
    private var commands: some View {
        ForEach(WindowCommandCatalog.grouped(), id: \.group) { section in
            Section {
                ForEach(section.commands) { command in
                    WindowCommandSettingsRow(command: command)
                }
            } header: {
                Text(section.group.title)
            }
        }
    }
}

/// One command's shortcut recorder and visibility checkbox, shaped like the shortcuts row.
private struct WindowCommandSettingsRow: View {
    let command: WindowCommand
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(title: command.name) {
            Image(systemName: command.sfSymbol)
        } trailing: {
            ShortcutRecorder(action: .windowCommand(id: command.id))

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel("Show \(command.name) in launcher")
        }
    }

    /// `VisibilityStore` keys on the entry, so this builds the same entry `AppIndex` publishes.
    private var entry: AppEntry {
        AppEntry(
            id: command.entryID, name: command.name,
            url: URL(string: "tinycast://window-command/" + command.id.rawValue)!, bundleID: nil,
            kind: .windowCommand)
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }
}
