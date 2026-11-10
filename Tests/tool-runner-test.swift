import Foundation

@main
struct ToolRunnerTest {
    static func main() async throws {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        let cat = URL(fileURLWithPath: "/bin/cat")
        let echoed = try await ToolRunner.run(cat, ["-"], standardInput: Data("on".utf8))
        check("standard input reaches the tool", echoed.output == "on")
        check("the tool sees end of input and exits", echoed.succeeded)

        // Well past a pipe's buffer: the write outlives the tool, and must fail rather than SIGPIPE.
        let ignored = try await ToolRunner.run(
            URL(fileURLWithPath: "/usr/bin/true"), [], standardInput: Data(count: 4_000_000))
        check("a tool that never reads still finishes", ignored.succeeded)

        let large = Data(repeating: 0x61, count: 1_000_000)
        let drained = try await ToolRunner.run(cat, ["-"], standardInput: large)
        check("input larger than the pipe arrives whole", drained.output.utf8.count == large.count)

        exit(failures == 0 ? 0 : 1)
    }
}
