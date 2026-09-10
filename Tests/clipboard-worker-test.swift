import CoreText
import Foundation
import ImageIO

@main @MainActor
struct ClipboardWorkerTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-worker-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("ClipboardTextHelper")
        try compile([
            "Tinycast/Features/Clipboard/Service/ClipboardTextExtractor.swift",
            "Tinycast/Features/Clipboard/Service/ClipboardTextHelper.swift"
        ], to: executable)
        let source = directory.appendingPathComponent("receipt.png")
        let context = CGContext(
            data: nil, width: 1000, height: 300, bitsPerComponent: 8, bytesPerRow: 4000,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 300))
        context.textPosition = CGPoint(x: 40, y: 150)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(
            string: "ALPINE RECEIPT 7391", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String):
                    CTFontCreateWithName("Helvetica" as CFString, 48, nil)
            ])), context)
        let destination = CGImageDestinationCreateWithURL(source as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let text = try await Task.detached {
            try await ClipboardTextWorker.extract(at: source, isPDF: false, executable: executable)
        }.value
        precondition(text.contains("7391"), "packaged helper returns recognized text")
        do {
            _ = try await Task.detached {
                try await ClipboardTextWorker.extract(
                    at: directory.appendingPathComponent("missing.png"), isPDF: false, executable: executable)
            }.value
            preconditionFailure("helper errors must not become empty success")
        } catch ClipboardTextWorker.Failure.recognition { }

        let fixtureSource = directory.appendingPathComponent("fixture.swift")
        try """
            import Foundation
            let path = CommandLine.arguments[2]
            if path.hasSuffix("oversized") {
                FileHandle.standardOutput.write(Data(repeating: 65, count: 40_000))
            } else {
                try String(getpid()).write(toFile: path, atomically: true, encoding: .utf8)
                Thread.sleep(forTimeInterval: 30)
            }
            """.write(to: fixtureSource, atomically: true, encoding: .utf8)
        let fixture = directory.appendingPathComponent("fixture")
        try compile([fixtureSource.path], to: fixture, entryPoint: true)
        let pidFile = directory.appendingPathComponent("pid")
        let running = Task.detached {
            try await ClipboardTextWorker.extract(at: pidFile, isPDF: false, executable: fixture)
        }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8))!
        running.cancel()
        do {
            _ = try await running.value
            preconditionFailure("cancellation must propagate")
        } catch is CancellationError { }
        precondition(kill(pid, 0) == -1 && errno == ESRCH, "cancelled child is reaped")
        do {
            _ = try await Task.detached {
                try await ClipboardTextWorker.extract(
                    at: pidFile, isPDF: false, executable: fixture, timeout: .milliseconds(100))
            }.value
            preconditionFailure("deadline must stop stuck helpers")
        } catch ClipboardTextWorker.Failure.recognition { }
        let timedOutPID = Int32(try String(contentsOf: pidFile, encoding: .utf8))!
        precondition(kill(timedOutPID, 0) == -1 && errno == ESRCH, "timed-out child is reaped")
        do {
            _ = try await Task.detached {
                try await ClipboardTextWorker.extract(
                    at: directory.appendingPathComponent("oversized"), isPDF: false, executable: fixture)
            }.value
            preconditionFailure("helper output must stay bounded")
        } catch ClipboardTextWorker.Failure.outputLimit { }
        print("Helper recognition, errors, cancellation, deadline and bounded output passed")
    }

    static func compile(_ sources: [String], to executable: URL, entryPoint: Bool = false) throws {
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-swift-version", "6"]
            + (entryPoint ? [] : ["-parse-as-library"]) + sources + ["-o", executable.path]
        try compiler.run()
        compiler.waitUntilExit()
        precondition(compiler.terminationStatus == 0, "fixture compilation")
    }
}
