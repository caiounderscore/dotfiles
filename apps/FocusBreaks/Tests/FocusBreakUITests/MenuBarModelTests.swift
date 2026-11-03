import Foundation
import FocusBreakCore
import Testing
@testable import FocusBreakUI

@MainActor
struct MenuBarModelTests {
    @Test("renders phase and remaining time")
    func rendersStatus() {
        let model = MenuBarModel(sender: FakeCommandSender())

        model.apply(
            SessionSnapshot(sessionID: UUID(), phase: .working, revision: 1),
            remaining: 49 * 60 + 5
        )

        #expect(model.statusTitle == "Focus")
        #expect(model.remainingText == "49:05")
        #expect(model.canPause)
        #expect(model.canResume == false)
    }

    @Test("routes controls through the coordinator client")
    func routesControls() async {
        let sender = FakeCommandSender()
        let model = MenuBarModel(sender: sender)

        await model.send(.start)
        await model.send(.pause)

        #expect(sender.commands == [.start, .pause])
        #expect(model.snapshot.phase == .paused)
        #expect(model.errorMessage == nil)
    }
}

@MainActor
private final class FakeCommandSender: SessionCommandSending {
    private(set) var commands: [SessionCommand] = []

    func send(_ command: SessionCommand) async throws -> SessionSnapshot {
        commands.append(command)
        return SessionSnapshot(
            sessionID: UUID(),
            phase: command == .pause ? .paused : .working,
            revision: commands.count
        )
    }


    func configure(_ plan: DailySessionPlan) async throws -> SessionSnapshot {
        SessionSnapshot()
    }
}
