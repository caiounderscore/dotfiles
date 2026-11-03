import FocusBreakCore
import Foundation

private let commandNames: [String: SessionCommand] = [
    "start": .start,
    "status": .status,
    "pause": .pause,
    "resume": .resume,
    "snooze": .snooze,
    "skip": .skip,
    "stop": .stop,
]

guard CommandLine.arguments.count == 2,
      let command = commandNames[CommandLine.arguments[1]] else {
    FileHandle.standardError.write(
        Data("Usage: focusctl <start|status|pause|resume|snooze|skip|stop>\n".utf8)
    )
    exit(64)
}

do {
    let paths = try FocusBreakRuntimePaths.userDefault()
    let client = CoordinatorSocketClient(socketURL: paths.socketURL)
    let response = try await client.send(
        SessionRequest(requestID: UUID(), command: command)
    )
    print("\(response.snapshot.phase.rawValue) revision=\(response.snapshot.revision)")
} catch {
    FileHandle.standardError.write(
        Data("focusctl: the Focus Breaks coordinator is unavailable\n".utf8)
    )
    exit(69)
}
