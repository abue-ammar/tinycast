import SwiftUI

@main
struct SmallcastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only when the value changes, avoiding a scene ⇄ binding feedback loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // Channel-aware: "Smallcast", "Smallcast Dev", or "Smallcast Beta".
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(
            appName, systemImage: "macwindow.on.rectangle", isInserted: $showInMenuBar
        ) {
            Button("Open \(appName)") { AppCore.shared.showPalette(mode: .launcher) }
            Button("Clipboard History") { AppCore.shared.showPalette(mode: .clipboard) }
            Divider()
            Button("Settings...") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit \(appName)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
