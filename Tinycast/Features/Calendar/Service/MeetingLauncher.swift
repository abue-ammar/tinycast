import AppKit

enum MeetingLauncher {
    struct Browser: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// A missing `browserBundleID` app falls back to the default browser, never a failed join.
    @MainActor
    static func join(_ link: MeetingLink, browserBundleID: String?) async -> Bool {
        let workspace = NSWorkspace.shared
        if let appURL = link.appURL, workspace.urlForApplication(toOpen: appURL) != nil {
            return workspace.open(appURL)
        }
        guard let browserBundleID,
            let browser = workspace.urlForApplication(withBundleIdentifier: browserBundleID)
        else { return workspace.open(link.webURL) }
        do {
            _ = try await workspace.open(
                [link.webURL], withApplicationAt: browser,
                configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            return false
        }
    }

    /// Every app that opens `https`, one per bundle ID, sorted by name.
    @MainActor
    static func installedBrowsers() -> [Browser] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .compactMap { url -> Browser? in
                guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted
                else { return nil }
                return Browser(id: id, name: url.deletingPathExtension().lastPathComponent)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Calendar.app's own handle; a recurring occurrence opens its series.
    @MainActor
    @discardableResult
    static func showInCalendar(_ event: MeetingEvent) -> Bool {
        let workspace = NSWorkspace.shared
        guard
            let url = URL(
                string: "ical://ekevent/\(event.calendarItemID)?method=show&options=more")
        else { return false }
        // The default calendar app owns webcal; only Calendar.app reads ical:// links.
        if let webcal = URL(string: "webcal://"), let app = workspace.urlForApplication(toOpen: webcal),
            app != workspace.urlForApplication(toOpen: url)
        {
            return workspace.open(app)
        }
        return workspace.open(url)
    }
}
