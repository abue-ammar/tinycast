import SwiftUI

struct MonitorControlSettingsView: View {
    var body: some View {
        Form {
            MonitorControlSettingsSection()
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.monitorControl)
        .releasesFocusOnOutsideClick()
    }
}
