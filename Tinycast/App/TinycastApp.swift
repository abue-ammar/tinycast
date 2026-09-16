import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only on change, avoiding a scene ⇄ binding loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // Channel-aware: "Tinycast", "Tinycast Dev", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    /// Two independent items: each inserted by its own answer, reading no state off the other.
    var body: some Scene {
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }

        // Read in `body`, where Observation tracks it, not only inside the binding's getter.
        let calendarInserted = AppCore.shared.calendarCoordinator.isMenuBarItemInserted
        MenuBarExtra(isInserted: calendarMenuBarInsertion(calendarInserted)) {
            CalendarMenuBarMenu()
        } label: {
            CalendarMenuBarLabel(appName: appName)
        }
    }

    /// Writes through `AppSettings`, so a drag-out also stops the clock and moves the picker.
    private func calendarMenuBarInsertion(_ inserted: Bool) -> Binding<Bool> {
        Binding(get: { inserted }, set: { calendarMenuBarInsertionDidChange(to: $0) })
    }

    /// Handed back after every change, so `false` is a drag-out only while the item should be up.
    private func calendarMenuBarInsertionDidChange(to inserted: Bool) {
        let core = AppCore.shared
        if !inserted {
            guard core.calendarCoordinator.isMenuBarItemInserted else { return }
            core.settings.calendarMenuBarDisplay = .disabled
        } else if core.settings.calendarMenuBarDisplay == .disabled {
            core.settings.calendarMenuBarDisplay = .meetingIcon
        }
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
