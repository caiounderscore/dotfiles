import Darwin
import Foundation
import Testing
@testable import FocusBreakCore

struct CoordinatorTransportTests {
    @Test("round-trips a request through the local coordinator socket")
    func roundTripsRequest() async throws {
        try await withTemporaryDirectory { directory in
            let server = try CoordinatorSocketServer(runtimeDirectory: directory)
            let coordinator = SessionCoordinator()
            let request = SessionRequest(requestID: UUID(), command: .start)

            async let serving: Void = server.serveOnce { request in
                try await coordinator.handle(request)
            }
            let response = try await CoordinatorSocketClient(socketURL: server.socketURL)
                .send(request)
            try await serving

            #expect(response.requestID == request.requestID)
            #expect(response.snapshot.phase == .working)
        }
    }

    @Test("runtime directory and socket are accessible only to the current user")
    func appliesPrivatePermissions() throws {
        try withTemporaryDirectory { directory in
            let lockURL = directory.appendingPathComponent("coordinator.lock")
            try Data().write(to: lockURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: lockURL.path
            )
            let server = try CoordinatorSocketServer(runtimeDirectory: directory)

            let directoryMode = try permissions(at: directory)
            let lockMode = try permissions(at: lockURL)
            let socketMode = try permissions(at: server.socketURL)
            #expect(directoryMode == 0o700)
            #expect(lockMode == 0o600)
            #expect(socketMode == 0o600)
        }
    }

    @Test("exclusive lock rejects a second coordinator")
    func rejectsSecondCoordinator() throws {
        try withTemporaryDirectory { directory in
            let server = try CoordinatorSocketServer(runtimeDirectory: directory)
            _ = server

            #expect(throws: CoordinatorTransportError.alreadyRunning) {
                try CoordinatorSocketServer(runtimeDirectory: directory)
            }
        }
    }

    @Test("removes a stale socket only after acquiring the coordinator lock")
    func replacesStaleSocket() throws {
        try withTemporaryDirectory { directory in
            let socketURL = directory.appendingPathComponent("coordinator.sock")
            try Data().write(to: socketURL)

            let server = try CoordinatorSocketServer(runtimeDirectory: directory)
            let attributes = try FileManager.default.attributesOfItem(atPath: server.socketURL.path)

            #expect(attributes[.type] as? FileAttributeType == .typeSocket)
        }
    }

    @Test("ignores a disconnected client and serves the next valid request")
    func toleratesDisconnectedClient() async throws {
        try await withTemporaryDirectory { directory in
            let server = try CoordinatorSocketServer(runtimeDirectory: directory)
            let coordinator = SessionCoordinator()

            async let serving: Void = server.serveOnce { request in
                try await coordinator.handle(request)
            }
            try connectAndDisconnect(socketURL: server.socketURL)
            let response = try await CoordinatorSocketClient(socketURL: server.socketURL).send(
                SessionRequest(requestID: UUID(), command: .start)
            )
            try await serving

            #expect(response.snapshot.phase == .working)
        }
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    private func connectAndDisconnect(socketURL: URL) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CoordinatorTransportError.systemCallFailed
        }
        defer { close(descriptor) }
        try CoordinatorSocketAddress(socketURL: socketURL).connect(descriptor: descriptor)
    }

    private func withTemporaryDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("FB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("FB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
