import SwiftUI

struct ExtensionsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.extensionsEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .extensionsExtensions, title: "Enable Extensions",
                        subtitle: "Run extension commands from the launcher.")
                }
            }
            .settingsAnchor(.extensionsExtensions)

            #if DEBUG
                ExtensionDeveloperModeSection()
                    .disabled(!settings.extensionsEnabled)
            #endif
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.extensions)
    }
}

#if DEBUG
    /// Debug builds only, so its text stays out of the catalog that Release ships.
    private struct ExtensionDeveloperModeSection: View {
        @Environment(AppSettings.self) private var settings

        var body: some View {
            @Bindable var settings = settings
            Section {
                Toggle(isOn: $settings.extensionDeveloperMode) {
                    Text(verbatim: "Run bundles from the developer folder")
                }
                LabeledContent {
                    Button {
                        showFolder()
                    } label: {
                        Text(verbatim: "Show in Finder")
                    }
                } label: {
                    Text(verbatim: ExtensionBundle.developerFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text(verbatim: "Developer Mode")
            } footer: {
                Text(
                    verbatim: """
                        Packed .tcext bundles here, or symlinks to them, run without the Store or a \
                        signature check.
                        """)
            }
        }

        private func showFolder() {
            let folder = ExtensionBundle.developerFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }
#endif
