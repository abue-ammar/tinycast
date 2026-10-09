import AppKit
import Foundation

let arguments = CommandLine.arguments
if arguments.count != 4 { exit(2) }
let mode = arguments[1]
let bundleID = arguments[2]
let bundleURL = URL(fileURLWithPath: arguments[3]).resolvingSymlinksInPath()
let owned = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
    $0.bundleURL?.resolvingSymlinksInPath() == bundleURL
}
if mode == "inspect" {
    var data = try JSONSerialization.data(withJSONObject: owned.map { Int($0.processIdentifier) })
    data.append(0x0a)
    FileHandle.standardOutput.write(data)
} else if mode == "stop" {
    for application in owned { application.terminate() }
    for _ in 0..<50 {
        if owned.allSatisfy(\.isTerminated) { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    for application in owned where !application.isTerminated { application.forceTerminate() }
} else { exit(2) }
