import Foundation

public struct FocusBreakRuntimePaths: Sendable {
    public let rootDirectory: URL
    public let runtimeDirectory: URL
    public let stateDirectory: URL
    public let socketURL: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        runtimeDirectory = rootDirectory.appendingPathComponent("runtime", isDirectory: true)
        stateDirectory = rootDirectory.appendingPathComponent("state", isDirectory: true)
        socketURL = runtimeDirectory.appendingPathComponent("coordinator.sock", isDirectory: false)
    }

    public static func userDefault(
        fileManager: FileManager = .default
    ) throws -> FocusBreakRuntimePaths {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FocusBreakRuntimePaths(
            rootDirectory: applicationSupport
                .appendingPathComponent("FocusBreaks", isDirectory: true)
        )
    }
}
