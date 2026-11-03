import Foundation
import Testing
@testable import FocusBreakCore

struct SessionStateStoreTests {
    @Test("atomically round-trips current-day coordinator state")
    func roundTripsState() async throws {
        try await withTemporaryDirectory { directory in
            let store = SessionStateStore(directory: directory)
            let coordinator = SessionCoordinator()
            _ = try await coordinator.handle(
                SessionRequest(requestID: UUID(), command: .start)
            )
            let record = await SessionStateRecord(
                localDay: "2026-07-20",
                coordinator: coordinator.exportState()
            )

            try store.save(record)
            let recovered = try store.load(for: "2026-07-20")
            let loaded = try #require(recovered)

            #expect(loaded == record)
            #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.contains(".tmp") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test("does not recover state from another local day")
    func rejectsPreviousDay() throws {
        try withTemporaryDirectory { directory in
            let store = SessionStateStore(directory: directory)
            try store.save(
                SessionStateRecord(
                    localDay: "2026-07-19",
                    coordinator: SessionCoordinatorState()
                )
            )

            #expect(try store.load(for: "2026-07-20") == nil)
        }
    }

    @Test("requires an explicit resume or discard recovery decision")
    func resolvesRecoveryExplicitly() {
        let state = SessionCoordinatorState(
            snapshot: SessionSnapshot(
                sessionID: UUID(),
                phase: .working,
                revision: 1
            )
        )
        let record = SessionStateRecord(localDay: "2026-07-20", coordinator: state)

        #expect(SessionRecovery.resolve(record, decision: .resume) == state)
        #expect(SessionRecovery.resolve(record, decision: .discard) == nil)
    }

    @Test("preserves request deduplication across coordinator recovery")
    func preservesIdempotencyLedger() async throws {
        let original = SessionCoordinator()
        _ = try await original.handle(SessionRequest(requestID: UUID(), command: .start))
        let pause = SessionRequest(requestID: UUID(), command: .pause)
        let first = try await original.handle(pause)
        let restored = SessionCoordinator(state: await original.exportState())

        let retried = try await restored.handle(pause)

        #expect(retried == first)
        #expect(await restored.snapshot.revision == 2)
    }

    @Test("rejects a state schema from a newer application")
    func rejectsUnknownSchema() throws {
        try withTemporaryDirectory { directory in
            let store = SessionStateStore(directory: directory)
            let unsupported = SessionStateRecord(
                schemaVersion: 2,
                localDay: "2026-07-20",
                coordinator: SessionCoordinatorState()
            )
            try JSONEncoder().encode(unsupported).write(to: store.fileURL)

            #expect(throws: SessionStateStoreError.unsupportedSchema) {
                try store.load(for: "2026-07-20")
            }
        }
    }

    private func withTemporaryDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusBreaksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusBreaksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
