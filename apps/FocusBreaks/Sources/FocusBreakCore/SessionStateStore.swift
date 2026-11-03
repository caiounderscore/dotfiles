import Foundation

public struct SessionStateRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let localDay: String
    public let coordinator: SessionCoordinatorState

    public init(
        schemaVersion: Int = 1,
        localDay: String,
        coordinator: SessionCoordinatorState
    ) {
        self.schemaVersion = schemaVersion
        self.localDay = localDay
        self.coordinator = coordinator
    }
}

public enum SessionStateStoreError: Error, Equatable {
    case unsupportedSchema
}

public struct SessionStateStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("session-state.json", isDirectory: false)
    }

    public func save(_ record: SessionStateRecord) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func load(for localDay: String) throws -> SessionStateRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let record = try JSONDecoder().decode(SessionStateRecord.self, from: data)
        guard record.schemaVersion == 1 else {
            throw SessionStateStoreError.unsupportedSchema
        }
        guard record.localDay == localDay else {
            return nil
        }
        return record
    }
}

public enum SessionRecoveryDecision: Equatable, Sendable {
    case resume
    case discard
}

public enum SessionRecovery {
    public static func resolve(
        _ record: SessionStateRecord,
        decision: SessionRecoveryDecision
    ) -> SessionCoordinatorState? {
        switch decision {
        case .resume:
            record.coordinator
        case .discard:
            nil
        }
    }
}
