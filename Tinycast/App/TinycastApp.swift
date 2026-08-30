import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only on change, avoiding a scene ⇄ binding loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @AppStorage(SettingsKey.calendarMenuBarDisplay)
    private var calendarMenuBarDisplay = CalendarMenuBarDisplay.disabled.rawValue

    // Channel-aware: "Tinycast", "Tinycast Dev", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    /// Before `body`, and so before the first `AppCore.shared`: no store may open at the old path.
    init() {
        StorageRelocation.run()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: launcherMenuBarInsertion) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }

        MenuBarExtra(isInserted: calendarMenuBarInsertion) {
            MenuBarMenu(appName: appName)
        } label: {
            CalendarMenuBarLabel(appName: appName)
        }
    }

    private var calendarMenuBarInsertion: Binding<Bool> {
        Binding(
            get: { calendarMenuBarDisplay != CalendarMenuBarDisplay.disabled.rawValue },
            set: { inserted in
                if inserted {
                    if calendarMenuBarDisplay == CalendarMenuBarDisplay.disabled.rawValue {
                        calendarMenuBarDisplay = CalendarMenuBarDisplay.meetingIcon.rawValue
                    }
                } else {
                    calendarMenuBarDisplay = CalendarMenuBarDisplay.disabled.rawValue
                }
            })
    }

    /// The calendar item replaces the launcher item while it is enabled, so the menu bar has one
    /// Tinycast entry instead of two. Turning the calendar display off restores the user's
    /// launcher preference immediately.
    private var launcherMenuBarInsertion: Binding<Bool> {
        Binding(
            get: {
                showInMenuBar
                    && calendarMenuBarDisplay == CalendarMenuBarDisplay.disabled.rawValue
            },
            set: { inserted in
                // SwiftUI may write `false` when the calendar takes this slot. That is not a user
                // request to hide the launcher permanently.
                guard calendarMenuBarDisplay == CalendarMenuBarDisplay.disabled.rawValue else {
                    return
                }
                showInMenuBar = inserted
            })
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

private struct MenuBarMenu: View {
    let appName: String

    var body: some View {
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
        Button("Support \(appName)...") { AppCore.shared.supportCoordinator.showSupport() }
        Button("Settings...") { AppCore.shared.settingsCoordinator.showSettings() }
            .keyboardShortcut(",")
        Divider()
        // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
        Button("Quit \(appName)") { NSApp.terminate(nil) }
    }
}
