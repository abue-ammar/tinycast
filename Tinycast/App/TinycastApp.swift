import SwiftUI

@main
enum TinycastLaunch {
    static func main() {
        AppSettings.pinLanguage()
        TinycastApp.main()
    }
}

struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let appName = Bundle.main.appDisplayName

    /// Two independent items: one preference each, no state either can read off the other.
    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
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

    /// Read in `body` for Observation; SwiftUI echoes the binding back, so only a change writes.
    private var menuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.showInMenuBar
        return Binding(
            get: { isInserted },
            set: { inserted in
                guard inserted != settings.showInMenuBar else { return }
                settings.showInMenuBar = inserted
            })
    }

    /// Writes through `AppSettings`: dragging the item out must stop the clock and move the picker.
    private var calendarMenuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.calendarMenuBarDisplay != .disabled && !isCalendarMenuBarHiddenWhenEmpty
        return Binding(
            get: { isInserted },
            set: { inserted in
                if inserted {
                    guard settings.calendarMenuBarDisplay == .disabled else { return }
                    settings.calendarMenuBarDisplay = .meetingIcon
                } else {
                    // SwiftUI echoes our own removal back; only a drag-out means "turn it off".
                    guard !isCalendarMenuBarHiddenWhenEmpty, settings.calendarMenuBarDisplay != .disabled
                    else { return }
                    settings.calendarMenuBarDisplay = .disabled
                }
            })
    }

    /// Read in `body`, so Observation re-runs the scene when the coordinator's flag flips.
    private var isCalendarMenuBarHiddenWhenEmpty: Bool {
        AppCore.shared.settings.calendarMenuBarHidesWhenEmpty
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
