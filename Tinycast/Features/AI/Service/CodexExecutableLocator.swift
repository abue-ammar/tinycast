import Foundation

/// Finds an installed AI CLI the way Terminal would; the app's own PATH is Finder's.
enum InstalledAIExecutableLocator {
    nonisolated static func locate(
        _ kind: InstalledAIKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> URL? {
        if let url = wellKnown(kind, environment: environment).first(where: isExecutable) {
            return url
        }
        guard let path = await loginShellLookup(kind) else { return nil }
        let url = URL(fileURLWithPath: path)
        return isExecutable(url) ? url : nil
    }

    nonisolated private static func wellKnown(
        _ kind: InstalledAIKind, environment: [String: String]
    ) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: kind.command) }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin"].map {
            URL(fileURLWithPath: $0).appending(path: kind.command)
        }
        candidates += [".local/bin", ".npm-global/bin", ".volta/bin", ".bun/bin"].map {
            home.appending(path: $0).appending(path: kind.command)
        }
        if kind == .claude {
            candidates.append(home.appending(path: ".claude/local/claude"))
        }
        candidates += nvmInstalls(kind, in: home)
        return candidates
    }

    /// nvm keeps one `bin` per Node version; the newest is the one `nvm use default` would pick.
    nonisolated private static func nvmInstalls(
        _ kind: InstalledAIKind, in home: URL
    ) -> [URL] {
        let versions = home.appending(path: ".nvm/versions/node")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        return names
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { versions.appending(path: $0).appending(path: "bin/" + kind.command) }
    }

    nonisolated private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// `-i` reads the rc file that puts a version manager on PATH; a watchdog bounds a hang.
    nonisolated private static func loginShellLookup(_ kind: InstalledAIKind) async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-ilc", "command -v " + kind.command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["TINYCAST": "1"]
            ) { _, new in new }
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
            let path = (String(bytes: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.hasPrefix("/") ? path : nil
        }.value
    }
}

enum CodexExecutableLocator {
    nonisolated static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> URL? {
        await InstalledAIExecutableLocator.locate(.codex, environment: environment)
    }
}
