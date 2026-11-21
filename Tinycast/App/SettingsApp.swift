import SwiftUI

/// Settings' own process: one window, with the menus a titled window needs and nothing else.
struct SettingsApp: App {
    @NSApplicationDelegateAdaptor(SettingsAppDelegate.self) private var delegate

    private let appName = Bundle.main.appDisplayName

    /// A scene SwiftUI never opens by itself; it is here only to carry the menus.
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About \(appName)") { AppCore.shared.settingsCoordinator.showAbout() }
                    Button("Check for Updates…") { AppCore.shared.mainApp?.send(.checkForUpdates) }
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                        .keyboardShortcut(",")
                }
                CommandGroup(replacing: .appTermination) {
                    Button("Close Window") { AppCore.shared.settingsCoordinator.closeSettings() }
                        .keyboardShortcut("q")
                }
            }
    }
}

final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    /// Before any window: built first, one joins a fullscreen Space its menus never reach.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ProcessDisplayName.set(String(localized: "\(Bundle.main.appDisplayName) (Settings)"))
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.startSettings()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { AppCore.shared.mainApp?.open(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.settingsCoordinator.showSettings()
        return true
    }

    /// The window's close ends the process, so a closed last window must not end it first.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let deferred = AppCore.shared.mainApp?.prepareToClose {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return deferred == true ? .terminateLater : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCore.shared.prepareSettingsForTermination()
    }
}
