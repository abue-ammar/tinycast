import Foundation

@main
nonisolated enum ClipboardTextHelper {
    static func main() async {
        guard CommandLine.arguments.count == 3,
            ["image", "pdf"].contains(CommandLine.arguments[1])
        else { exit(2) }
        do {
            let text = try await ClipboardTextExtractor.extract(
                at: URL(fileURLWithPath: CommandLine.arguments[2]),
                isPDF: CommandLine.arguments[1] == "pdf")
            try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
        } catch {
            exit(1)
        }
    }
}
