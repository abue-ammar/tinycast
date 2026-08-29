import Foundation

/// Finds the user's `codex` the way their Terminal would; the app's own PATH is Finder's.
enum CodexExecutableLocator {
    nonisolated static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> URL? {
        if let url = wellKnown(environment: environment).first(where: isExecutable) { return url }
        guard let path = await loginShellLookup() else { return nil }
        let url = URL(fileURLWithPath: path)
        return isExecutable(url) ? url : nil
    }

    nonisolated private static func wellKnown(environment: [String: String]) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "codex") }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin"].map {
            URL(fileURLWithPath: $0).appending(path: "codex")
        }
        candidates += [".local/bin", ".npm-global/bin", ".volta/bin", ".bun/bin"].map {
            home.appending(path: $0).appending(path: "codex")
        }
        candidates += nvmInstalls(in: home)
        return candidates
    }

    /// nvm keeps one `bin` per Node version; the newest is the one `nvm use default` would pick.
    nonisolated private static func nvmInstalls(in home: URL) -> [URL] {
        let versions = home.appending(path: ".nvm/versions/node")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        return
            names
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { versions.appending(path: $0).appending(path: "bin/codex") }
    }

    nonisolated private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// `-i` reads the rc file that puts a version manager on PATH; a watchdog bounds a hang.
    nonisolated private static func loginShellLookup() async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-ilc", "command -v codex"]
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
}
