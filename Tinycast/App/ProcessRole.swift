import Foundation

/// A part of Tinycast run as this executable with its identity, so only Tinycast's code runs as one.
nonisolated enum ProcessRole: String, Sendable {
    case main
    case settings

    static let current: ProcessRole =
        CommandLine.arguments.lazy
        .compactMap { $0.hasPrefix(prefix) ? ProcessRole(rawValue: String($0.dropFirst(prefix.count))) : nil }
        .first ?? .main

    var argument: String { Self.prefix + rawValue }

    private static let prefix = "--role="
}
