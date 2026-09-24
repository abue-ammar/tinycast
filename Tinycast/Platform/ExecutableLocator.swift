import Foundation

/// Finds a user's CLI the way their Terminal would; the app's own PATH is Finder's.
enum ExecutableLocator {
    /// `extraHomePaths` are home-relative executable paths for installs that own no shared `bin`.
    nonisolated static func locate(
        _ command: String,
        extraHomePaths: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> URL? {
        // The shell's answer wins: a stale install in a well-known prefix can shadow the working one.
        if let path = await loginShellLookup(command) {
            let url = URL(fileURLWithPath: path)
            if isExecutable(url) { return url }
        }
        return wellKnown(command, extraHomePaths: extraHomePaths, environment: environment)
            .first(where: isExecutable)
    }

    /// An npm or Homebrew CLI is `env node`, and Finder's PATH has no `node` for it to find.
    nonisolated static func environment(
        running executable: URL,
        adding extra: [String: String] = [:],
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let paths =
            [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
            + [inherited["PATH"] ?? "/usr/bin:/bin"]
        return
            inherited
            .merging(extra) { _, new in new }
            .merging(["NO_COLOR": "1", "PATH": paths.joined(separator: ":")]) { _, new in new }
    }

    nonisolated private static func wellKnown(
        _ command: String, extraHomePaths: [String], environment: [String: String]
    ) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: command) }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin"].map {
            URL(fileURLWithPath: $0).appending(path: command)
        }
        candidates += [".local/bin", ".npm-global/bin", ".volta/bin", ".bun/bin", ".cargo/bin"].map {
            home.appending(path: $0).appending(path: command)
        }
        candidates += extraHomePaths.map { home.appending(path: $0) }
        candidates += nvmInstalls(command, in: home)
        return candidates
    }

    /// nvm keeps one `bin` per Node version; the newest is the one `nvm use default` would pick.
    nonisolated private static func nvmInstalls(_ command: String, in home: URL) -> [URL] {
        let versions = home.appending(path: ".nvm/versions/node")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        return
            names
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { versions.appending(path: $0).appending(path: "bin/\(command)") }
    }

    nonisolated private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// `-i` reads the rc file that puts a version manager on PATH; a watchdog bounds a hang.
    nonisolated private static func loginShellLookup(_ command: String) async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = loginShell()
            process.arguments = ["-ilc", #"command -v -- "$1""#, "tinycast-locator", command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.environment = ProcessInfo.processInfo.environment.merging(["TINYCAST": "1"]) {
                _, new in new
            }
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let stdout = Pipe()
            process.standardOutput = stdout
            do { try process.run() } catch { return nil }
            let watchdog = Task {
                try await Task.sleep(for: .seconds(5))
                if process.isRunning { process.terminate() }
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.hasPrefix("/") ? path : nil
        }.value
    }

    /// The lookup script is POSIX, so a shell like fish falls back to zsh, the macOS default.
    nonisolated private static func loginShell() -> URL {
        let posixShells: Set = ["zsh", "bash", "sh", "ksh", "dash"]
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else {
            return URL(fileURLWithPath: "/bin/zsh")
        }
        let url = URL(fileURLWithPath: String(cString: shell))
        return posixShells.contains(url.lastPathComponent) ? url : URL(fileURLWithPath: "/bin/zsh")
    }
}
