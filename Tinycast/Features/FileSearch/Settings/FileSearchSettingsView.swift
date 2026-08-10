import SwiftUI

struct FileSearchSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.fileSearchEnabled) {
                    Text("Enable File Search")
                    Text("Find files and folders through the system Spotlight index, only on demand.")
                }
            } header: {
                Text("File Search")
            }
        }
        .formStyle(.grouped)
    }
}
