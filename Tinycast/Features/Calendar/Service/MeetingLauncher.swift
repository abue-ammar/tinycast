import AppKit

enum MeetingLauncher {

    /// The desktop app where one claims the scheme, the web where it does not. Returns false only
    /// when neither route exists, which is what the caller reports.
    @MainActor
    @discardableResult
    static func join(_ link: MeetingLink) -> Bool {
        if let appURL = link.appURL, NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            return NSWorkspace.shared.open(appURL)
        }
        return NSWorkspace.shared.open(link.url)
    }

    /// Calendar.app's own handle. A recurring occurrence opens its series, which is all `ical://` takes.
    @MainActor
    @discardableResult
    static func showInCalendar(_ event: MeetingEvent) -> Bool {
        guard
            let url = URL(
                string: "ical://ekevent/\(event.calendarItemID)?method=show&options=more")
        else { return false }
        return NSWorkspace.shared.open(url)
    }
}
