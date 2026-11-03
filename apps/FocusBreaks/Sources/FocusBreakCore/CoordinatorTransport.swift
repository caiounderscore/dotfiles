import Darwin
import Foundation

public enum CoordinatorTransportError: Error, Equatable {
    case alreadyRunning
    case disconnected
    case invalidSocketPath
    case messageTooLarge
    case peerRejected
    case protocolViolation
    case systemCallFailed
}

public struct CoordinatorSocketAddress: Sendable {
    private let path: String

    public init(socketURL: URL) throws {
        path = socketURL.path
        guard path.utf8CString.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw CoordinatorTransportError.invalidSocketPath
        }
    }

    public func connect(descriptor: Int32) throws {
        let result = try withAddress { address, length in
            Darwin.connect(descriptor, address, length)
        }
        guard result == 0 else {
            throw CoordinatorTransportError.systemCallFailed
        }
    }

    fileprivate func bind(descriptor: Int32) throws {
        let result = try withAddress { address, length in
            Darwin.bind(descriptor, address, length)
        }
        guard result == 0 else {
            throw CoordinatorTransportError.systemCallFailed
        }
    }

    private func withAddress<Result>(
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
    ) throws -> Result {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = path.utf8CString
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }

        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

public final class CoordinatorSocketServer: @unchecked Sendable {
    public let socketURL: URL

    private let lockDescriptor: Int32
    private let socketDescriptor: Int32

    public init(runtimeDirectory: URL) throws {
        socketURL = runtimeDirectory.appendingPathComponent("coordinator.sock", isDirectory: false)
        let lockURL = runtimeDirectory.appendingPathComponent("coordinator.lock", isDirectory: false)

        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: runtimeDirectory.path
        )

        let openedLock = Darwin.open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard openedLock >= 0 else {
            throw CoordinatorTransportError.systemCallFailed
        }
        guard fchmod(openedLock, 0o600) == 0 else {
            Darwin.close(openedLock)
            throw CoordinatorTransportError.systemCallFailed
        }
        guard flock(openedLock, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(openedLock)
            throw CoordinatorTransportError.alreadyRunning
        }

        let openedSocket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard openedSocket >= 0 else {
            flock(openedLock, LOCK_UN)
            Darwin.close(openedLock)
            throw CoordinatorTransportError.systemCallFailed
        }

        do {
            let address = try CoordinatorSocketAddress(socketURL: socketURL)
            if FileManager.default.fileExists(atPath: socketURL.path),
               Darwin.unlink(socketURL.path) != 0 {
                throw CoordinatorTransportError.systemCallFailed
            }
            try address.bind(descriptor: openedSocket)
            guard chmod(socketURL.path, 0o600) == 0,
                  Darwin.listen(openedSocket, 16) == 0 else {
                throw CoordinatorTransportError.systemCallFailed
            }
        } catch {
            Darwin.close(openedSocket)
            flock(openedLock, LOCK_UN)
            Darwin.close(openedLock)
            throw error
        }

        lockDescriptor = openedLock
        socketDescriptor = openedSocket
    }

    deinit {
        Darwin.close(socketDescriptor)
        Darwin.unlink(socketURL.path)
        flock(lockDescriptor, LOCK_UN)
        Darwin.close(lockDescriptor)
    }

    public func serveOnce(
        handler: @escaping @Sendable (SessionRequest) async throws -> SessionResponse
    ) async throws {
        while true {
            do {
                let accepted = try await Task.detached {
                    try self.acceptRequest()
                }.value
                do {
                    let response = try await handler(accepted.request)
                    try Self.write(response, to: accepted.descriptor)
                    Darwin.close(accepted.descriptor)
                    return
                } catch {
                    Darwin.close(accepted.descriptor)
                    throw error
                }
            } catch CoordinatorTransportError.disconnected {
                continue
            }
        }
    }

    private func acceptRequest() throws -> (descriptor: Int32, request: SessionRequest) {
        let client = Darwin.accept(socketDescriptor, nil, nil)
        guard client >= 0 else {
            throw CoordinatorTransportError.systemCallFailed
        }

        do {
            try Self.requireCurrentUser(descriptor: client)
            let request: SessionRequest = try Self.read(from: client)
            return (client, request)
        } catch {
            Darwin.close(client)
            throw error
        }
    }

    private static func requireCurrentUser(descriptor: Int32) throws {
        var userID: uid_t = 0
        var groupID: gid_t = 0
        guard getpeereid(descriptor, &userID, &groupID) == 0 else {
            throw CoordinatorTransportError.systemCallFailed
        }
        guard userID == geteuid() else {
            throw CoordinatorTransportError.peerRejected
        }
    }

    fileprivate static func read<Value: Decodable>(from descriptor: Int32) throws -> Value {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while data.count <= 64 * 1024 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                throw CoordinatorTransportError.systemCallFailed
            }
            if count == 0 {
                guard data.isEmpty == false else {
                    throw CoordinatorTransportError.disconnected
                }
                break
            }

            data.append(contentsOf: buffer.prefix(count))
            if let newline = data.firstIndex(of: 0x0A) {
                data = data[..<newline]
                break
            }
        }

        guard data.count <= 64 * 1024 else {
            throw CoordinatorTransportError.messageTooLarge
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw CoordinatorTransportError.protocolViolation
        }
    }

    fileprivate static func write<Value: Encodable>(_ value: Value, to descriptor: Int32) throws {
        var noSignal: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                guard count > 0 else {
                    throw CoordinatorTransportError.systemCallFailed
                }
                written += count
            }
        }
    }
}

public struct CoordinatorSocketClient: Sendable {
    public let socketURL: URL

    public init(socketURL: URL) {
        self.socketURL = socketURL
    }

    public func send(_ request: SessionRequest) async throws -> SessionResponse {
        try await Task.detached {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw CoordinatorTransportError.systemCallFailed
            }
            defer { Darwin.close(descriptor) }

            try CoordinatorSocketAddress(socketURL: socketURL).connect(descriptor: descriptor)
            try CoordinatorSocketServer.write(request, to: descriptor)
            guard Darwin.shutdown(descriptor, SHUT_WR) == 0 else {
                throw CoordinatorTransportError.systemCallFailed
            }
            return try CoordinatorSocketServer.read(from: descriptor)
        }.value
    }
}
