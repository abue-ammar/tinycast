import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only when the value changes, avoiding a scene ⇄ binding feedback loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // Channel-aware: "Tinycast", "Tinycast Dev", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(
            appName, systemImage: "macwindow.on.rectangle", isInserted: $showInMenuBar
        ) {
            Button("Open \(appName)") { AppCore.shared.showPalette(mode: .launcher) }
            Button("Clipboard History") { AppCore.shared.showPalette(mode: .clipboard) }
            // Absent on the dev channel, which has no update feed.
            if AppCore.shared.updates.isSupported {
                Divider()
                Button("Check for Updates…") { AppCore.shared.checkForUpdates() }
            }
            Divider()
            Button("Settings...") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit \(appName)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
