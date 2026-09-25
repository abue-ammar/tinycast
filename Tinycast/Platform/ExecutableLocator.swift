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
        if let path = await shellLookup(command, shell: loginShell()) {
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
        candidates += [
            ".local/bin", ".npm-global/bin", ".volta/bin", ".bun/bin", ".cargo/bin",
            ".local/share/mise/shims", ".asdf/shims"
        ].map { home.appending(path: $0).appending(path: command) }
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
    nonisolated static func shellLookup(_ command: String, shell: URL) async -> String? {
        await Task.detached {
            let process = Process()
            let (executable, arguments) = lookup(command, in: shell)
            process.executableURL = executable
            process.arguments = arguments
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
            // An rc file that prints goes first, so the lookup's answer is the last line.
            let path = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline).last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return path.hasPrefix("/") ? path : nil
        }.value
    }

    /// fish binds `-c` arguments to `$argv`, not `$1`; any other shell falls back to zsh.
    nonisolated private static func lookup(_ command: String, in shell: URL) -> (URL, [String]) {
        switch shell.lastPathComponent {
        case "fish":
            return (shell, ["-ilc", "command -v -- $argv[1]", command])
        case "zsh", "bash", "sh", "ksh", "dash":
            return (shell, ["-ilc", #"command -v -- "$1""#, "tinycast-locator", command])
        default:
            return lookup(command, in: URL(fileURLWithPath: "/bin/zsh"))
        }
    }

    nonisolated private static func loginShell() -> URL {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else {
            return URL(fileURLWithPath: "/bin/zsh")
        }
        return URL(fileURLWithPath: String(cString: shell))
    }
}
