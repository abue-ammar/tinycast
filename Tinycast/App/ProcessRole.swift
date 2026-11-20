import Foundation

/// Which part of Tinycast this process runs; every role is this executable, sharing its identity.
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
