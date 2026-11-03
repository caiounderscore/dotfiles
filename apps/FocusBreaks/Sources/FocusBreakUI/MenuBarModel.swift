import FocusBreakCore
import Foundation
import Observation

@MainActor
public protocol SessionCommandSending: AnyObject {
    func send(_ command: SessionCommand) async throws -> SessionSnapshot
    func configure(_ plan: DailySessionPlan) async throws -> SessionSnapshot
}

@MainActor
public final class CoordinatorCommandSender: SessionCommandSending {
    private let client: CoordinatorSocketClient

    public init(socketURL: URL) {
        client = CoordinatorSocketClient(socketURL: socketURL)
    }

    public func send(_ command: SessionCommand) async throws -> SessionSnapshot {
        let request = SessionRequest(requestID: UUID(), command: command)
        return try await client.send(request).snapshot
    }

    public func configure(_ plan: DailySessionPlan) async throws -> SessionSnapshot {
        let request = SessionRequest(
            requestID: UUID(),
            command: .configure,
            dailyPlan: plan
        )
        return try await client.send(request).snapshot
    }
}

@MainActor
@Observable
public final class MenuBarModel {
    public private(set) var snapshot = SessionSnapshot()
    public private(set) var remaining: TimeInterval?
    public private(set) var errorMessage: String?

    @ObservationIgnored
    private let sender: any SessionCommandSending

    public init(sender: any SessionCommandSending) {
        self.sender = sender
    }

    public var statusTitle: String {
        switch snapshot.phase {
        case .inactive:
            "No active session"
        case .working:
            "Focus"
        case .breakDue:
            "Break due"
        case .overlayActive:
            remaining == 0 ? "Break complete" : "Break"
        case .paused:
            "Paused"
        case .completed:
            "Session complete"
        }
    }

    public var remainingText: String {
        guard let remaining else { return "--:--" }
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public var canPause: Bool {
        snapshot.phase == .working
    }

    public var canResume: Bool {
        snapshot.phase == .paused
    }

    public var canSkip: Bool {
        [.breakDue, .overlayActive].contains(snapshot.phase)
            && snapshot.firstDismissalUsed
    }

    public var canStop: Bool {
        ![.inactive, .completed].contains(snapshot.phase)
    }

    public func apply(_ snapshot: SessionSnapshot, remaining: TimeInterval? = nil) {
        self.snapshot = snapshot
        self.remaining = remaining
        errorMessage = nil
    }

    public func send(_ command: SessionCommand) async {
        do {
            apply(try await sender.send(command))
        } catch {
            errorMessage = "The focus coordinator is unavailable."
        }
    }

    public func reportNotificationError(_ message: String) {
        errorMessage = message
    }
}
