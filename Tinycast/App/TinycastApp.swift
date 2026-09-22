import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only on change, avoiding a scene ⇄ binding loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @AppStorage(SettingsKey.calendarMenuBarDisplay)
    private var calendarMenuBarDisplay = CalendarMenuBarDisplay.disabled.rawValue
    @AppStorage(SettingsKey.calendarMenuBarHidesWhenEmpty)
    private var calendarMenuBarHidesWhenEmpty = false

    // Channel-aware: "Tinycast", "Tinycast Dev", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    /// Two independent items: one preference each, no state either can read off the other.
    var body: some Scene {
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }

        MenuBarExtra(isInserted: calendarMenuBarInsertion) {
            CalendarMenuBarMenu()
        } label: {
            CalendarMenuBarLabel(appName: appName)
        }
    }

    /// Reads the raw preference so the scene invalidates, but writes through `AppSettings`: dragging
    /// the item out must also stop the clock and move the picker, not just the stored value.
    private var calendarMenuBarInsertion: Binding<Bool> {
        let isInserted =
            calendarMenuBarDisplay != CalendarMenuBarDisplay.disabled.rawValue
            && !isCalendarMenuBarHiddenWhenEmpty
        return Binding(
            get: { isInserted },
            set: { inserted in
                let settings = AppCore.shared.settings
                if !inserted {
                    // SwiftUI echoes our own removal back here; only a drag-out means "turn it off".
                    guard !isCalendarMenuBarHiddenWhenEmpty else { return }
                    settings.calendarMenuBarDisplay = .disabled
                } else if settings.calendarMenuBarDisplay == .disabled {
                    settings.calendarMenuBarDisplay = .meetingIcon
                }
            })
    }

    /// Read in `body`, so Observation re-runs the scene when the coordinator's flag flips.
    private var isCalendarMenuBarHiddenWhenEmpty: Bool {
        calendarMenuBarHidesWhenEmpty
            && !AppCore.shared.calendarCoordinator.hasMenuBarEvent
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
            Button("Close Window") {
                // The chat window closes itself when it is in front; otherwise ⌘Q is Settings'.
                guard !AppCore.shared.aiChatCoordinator.closeWindowIfKey() else { return }
                AppCore.shared.settingsCoordinator.closeSettings()
            }
            .keyboardShortcut("q")
        }
    }
}
