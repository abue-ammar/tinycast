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
            // `restoreAnyMode`, like the global hotkey: "Open Tinycast" is a generic summon, so it
            // restores whatever screen was up (a pending uninstall list, a within-timeout sub-screen)
            // rather than forcing a reset root search.
            Button("Open \(appName)") {
                AppCore.shared.showPalette(mode: .launcher, restoreAnyMode: true)
            }
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
