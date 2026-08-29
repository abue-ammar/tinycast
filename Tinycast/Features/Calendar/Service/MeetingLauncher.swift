import AppKit

enum MeetingLauncher {

    /// The desktop app where one claims the scheme, the web where none does.
    @MainActor
    @discardableResult
    static func join(_ link: MeetingLink) -> Bool {
        if let appURL = link.appURL, NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            return NSWorkspace.shared.open(appURL)
        }
        return NSWorkspace.shared.open(link.webURL)
    }

    /// Calendar.app's own handle; a recurring occurrence opens its series.
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
