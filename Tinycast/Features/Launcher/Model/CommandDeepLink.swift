import Foundation

enum CommandDeepLink {
    static func claims(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "tinycast" && url.host == "command"
    }

    static func parse(_ url: URL) -> CommandID? {
        guard claims(url), url.query == nil, url.fragment == nil else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count == 1,
            let command = CommandID(rawValue: "command:" + segments[0]), !command.isQueryDriven
        else { return nil }
        return command
    }

    static func url(for command: CommandID) -> URL? {
        guard !command.isQueryDriven else { return nil }
        return URL(string: "tinycast://" + command.rawValue.replacingOccurrences(of: ":", with: "/"))
    }
}
