import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only on change, avoiding a scene ⇄ binding loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // Channel-aware: "Tinycast", "Tinycast Dev", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(isInserted: $showInMenuBar) {
            if let meeting = AppCore.shared.calendarCoordinator.menuBarEvent {
                Button("Join \(meeting.title)") {
                    AppCore.shared.calendarCoordinator.join(meeting)
                }
                Divider()
            }
            Button("Open \(appName)") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
            }
            Button("Clipboard History") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
            Divider()
            Button("Check for Updates...") { AppCore.shared.updateCoordinator.checkForUpdates() }
            Button("Settings...") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
            Divider()
            // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
            Button("Quit \(appName)") { NSApp.terminate(nil) }
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(appName)") { AppCore.shared.settingsCoordinator.showAbout() }
            Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Settings") { AppCore.shared.settingsCoordinator.closeSettings() }
                .keyboardShortcut("q")
        }
    }
}
