import Foundation

/// Machine facts the Node shims answer from without a host call. Sent once, when the engine boots.
struct ExtensionBootConfig: Sendable {
    var arch: String
    var release: String
    var hostname: String
    var username: String
    var shell: String
    var homeDirectory: String
    var temporaryDirectory: String
    var workingDirectory: String
    var cpuCount: Int
    var totalMemory: Double
    var environmentVariables: [String: String]

    static func current(supportDirectory: URL) -> ExtensionBootConfig {
        let info = ProcessInfo.processInfo
        var arch = "arm64"
        #if arch(x86_64)
            arch = "x64"
        #endif
        // A GUI app inherits a bare environment; extensions shelling out expect a login-ish PATH.
        var variables = info.environment
        variables["PATH"] =
            (variables["PATH"].map { $0 + ":" } ?? "")
            + "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        variables["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path

        return ExtensionBootConfig(
            arch: arch,
            release: info.operatingSystemVersionString,
            hostname: info.hostName,
            username: NSUserName(),
            shell: info.environment["SHELL"] ?? "/bin/zsh",
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            temporaryDirectory: FileManager.default.temporaryDirectory.path,
            workingDirectory: supportDirectory.path,
            cpuCount: info.processorCount,
            totalMemory: Double(info.physicalMemory),
            environmentVariables: variables)
    }

    func jsonString() -> String {
        ExtensionRuntime.jsonString(
            from: [
                "node": [
                    "arch": arch,
                    "release": release,
                    "hostname": hostname,
                    "username": username,
                    "shell": shell,
                    "homedir": homeDirectory,
                    "tmpdir": temporaryDirectory,
                    "cwd": workingDirectory,
                    "cpus": cpuCount,
                    "totalmem": totalMemory,
                    "env": environmentVariables,
                    "execPath": ""
                ]
            ])
    }
}

/// Everything one command needs at mount time: its `environment`, resolved preferences, the cache
/// namespaces it may read synchronously, and its launch arguments.
struct ExtensionLaunchContext: Sendable {
    var extensionName: String
    var extensionTitle: String
    var commandName: String
    var commandMode: ExtensionCommandMode
    var assetsPath: String
    var supportPath: String
    var preferences: [String: ExtensionPreferenceValue]
    var caches: [String: [String: String]]
    var arguments: [String: String]
    var fallbackText: String?

    func jsonString() -> String {
        var environment: [String: Any] = [
            "extensionName": extensionName,
            "commandName": commandName,
            "commandMode": commandMode.rawValue,
            "assetsPath": assetsPath,
            "supportPath": supportPath,
            "isDevelopment": false,
            // Extensions gate features on this; report the API level the shim implements.
            "raycastVersion": ExtensionRuntimeVersion.raycastAPI,
            "textSize": "medium",
            "appearance": "dark",
            "launchType": "userInitiated",
            "canAccess": false
        ]
        environment["ownerOrAuthorName"] = extensionTitle

        var launchProps: [String: Any] = ["launchType": "userInitiated", "arguments": arguments]
        if let fallbackText { launchProps["fallbackText"] = fallbackText }

        return ExtensionRuntime.jsonString(
            from: [
                "environment": environment,
                "preferences": preferences.mapValues(\.jsonValue),
                "caches": caches,
                "launchProps": launchProps
            ])
    }
}

enum ExtensionRuntimeVersion {
    /// The @raycast/api version the bundled shim tracks. Surfaced as `environment.raycastVersion`.
    static let raycastAPI = "1.104.0"
}
