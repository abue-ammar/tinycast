import Foundation

/// This channel's own link scheme: `tinycast`, or `tinycast-dev` for Debug. Set in project.yml.
enum AppURLScheme {
    static let current: String = {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "TinycastURLScheme") as? String
        else { preconditionFailure("Info.plist must name TinycastURLScheme") }
        return scheme
    }()
}
