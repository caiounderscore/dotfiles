import Foundation
import Testing
@testable import FocusBreakCore

struct SessionStateMachineTests {
    @Test("moves through work, escalation, snooze, skip, and stop")
    func followsLegalTransitions() throws {
        var machine = SessionStateMachine()

        let started = try machine.apply(.start)
        #expect(started.phase == .working)
        #expect(started.sessionID != nil)

        #expect(try machine.apply(.workIntervalElapsed).phase == .overlayActive)
        #expect(try machine.apply(.snooze).phase == .breakDue)
        #expect(machine.snapshot.firstDismissalUsed)
        #expect(try machine.apply(.reminderEscalated).phase == .overlayActive)
        #expect(try machine.apply(.skip).phase == .working)
        #expect(try machine.apply(.stop).phase == .completed)
    }

    @Test("pause and resume restore an active work phase")
    func restoresPausedPhase() throws {
        var machine = SessionStateMachine()
        _ = try machine.apply(.start)
        #expect(try machine.apply(.pause).phase == .paused)
        let resumed = try machine.apply(.resume)
        #expect(resumed.phase == .working)
        #expect(resumed.resumePhase == nil)
    }

    @Test("rejects transitions that are invalid for the current phase")
    func rejectsInvalidTransition() {
        var machine = SessionStateMachine()

        #expect(throws: SessionTransitionError.invalidTransition) {
            try machine.apply(.pause)
        }
    }

    @Test("requires the emergency-dismiss flow before a break can be skipped")
    func rejectsDirectSkip() throws {
        var machine = SessionStateMachine()
        _ = try machine.apply(.start)
        _ = try machine.apply(.workIntervalElapsed)

        #expect(throws: SessionTransitionError.invalidTransition) {
            try machine.apply(.skip)
        }
    }
}

struct SessionCoordinatorTests {
    @Test("production coordinator rejects start until daily preflight is confirmed")
    func requiresDailyPlan() async {
        let coordinator = SessionCoordinator(requiresDailyPlan: true)

        await #expect(throws: SessionPlanError.planRequired) {
            try await coordinator.handle(
                SessionRequest(requestID: UUID(), command: .start)
            )
        }
    }

    @Test("restores a persisted coordinator only after an explicit recovery action")
    func restoresPersistedState() async throws {
        let original = SessionCoordinator()
        _ = try await original.handle(
            SessionRequest(requestID: UUID(), command: .start)
        )
        let saved = await original.exportState()
        let restored = SessionCoordinator()

        try await restored.restore(saved)

        #expect(await restored.snapshot == saved.snapshot)
        #expect(await restored.exportState() == saved)
    }

    @Test("confirmed daily plan advances one authoritative interval at a time")
    func advancesConfirmedPlan() async throws {
        let start = Date(timeIntervalSince1970: 1_721_488_400)
        let plan = try DailySessionPlan(
            localDay: "2026-07-20",
            intervals: [
                FocusInterval(kind: .work, start: start, end: start.addingTimeInterval(50 * 60)),
                FocusInterval(
                    kind: .shortBreak,
                    start: start.addingTimeInterval(50 * 60),
                    end: start.addingTimeInterval(60 * 60)
                ),
                FocusInterval(
                    kind: .work,
                    start: start.addingTimeInterval(60 * 60),
                    end: start.addingTimeInterval(110 * 60)
                ),
            ]
        )
        let startedAt = start.addingTimeInterval(10)
        let clock = TestClock(startedAt)
        let coordinator = SessionCoordinator(now: { clock.now })

        try await coordinator.configure(plan)
        let started = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .start, issuedAt: startedAt)
        ).snapshot
        let breakDue = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .workIntervalElapsed)
        ).snapshot
        clock.now = breakDue.deadline ?? clock.now
        let nextWork = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .completeBreak)
        ).snapshot

        #expect(started.currentInterval == plan.intervals[0])
        #expect(started.deadline == startedAt.addingTimeInterval(50 * 60))
        #expect(breakDue.currentInterval == plan.intervals[1])
        #expect(breakDue.phase == .overlayActive)
        #expect(breakDue.deadline == startedAt.addingTimeInterval(10 * 60))
        #expect(nextWork.currentInterval == plan.intervals[2])
        #expect(nextWork.deadline != plan.intervals[2].end)
        #expect(await coordinator.exportState().dailyPlan == plan)
    }

    @Test("pause and resume preserve the effective remaining work duration")
    func preservesPausedDuration() async throws {
        let start = Date(timeIntervalSince1970: 1_721_488_400)
        let plan = try DailySessionPlan(
            localDay: "2026-07-20",
            intervals: [
                FocusInterval(kind: .work, start: start, end: start.addingTimeInterval(50 * 60)),
            ]
        )
        let clock = TestClock(start)
        let coordinator = SessionCoordinator(now: { clock.now })
        try await coordinator.configure(plan)
        _ = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .start, issuedAt: start)
        )
        clock.now = start.addingTimeInterval(10 * 60)
        let paused = try await coordinator.handle(
            SessionRequest(
                requestID: UUID(),
                command: .pause,
                issuedAt: start.addingTimeInterval(10 * 60)
            )
        ).snapshot
        let resumedAt = start.addingTimeInterval(20 * 60)
        clock.now = resumedAt
        let resumed = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .resume, issuedAt: resumedAt)
        ).snapshot

        #expect(paused.deadline == nil)
        #expect(paused.pausedRemaining == TimeInterval(40 * 60))
        #expect(resumed.deadline == resumedAt.addingTimeInterval(40 * 60))
        #expect(resumed.pausedRemaining == nil)
    }

    @Test("rejects break completion before zero and accepts it at zero")
    func enforcesFullBreakDuration() async throws {
        let start = Date(timeIntervalSince1970: 1_721_488_400)
        let clock = TestClock(start)
        let plan = try DailySessionPlan(
            localDay: "2026-07-20",
            intervals: [
                FocusInterval(kind: .work, start: start, end: start.addingTimeInterval(50 * 60)),
                FocusInterval(
                    kind: .shortBreak,
                    start: start.addingTimeInterval(50 * 60),
                    end: start.addingTimeInterval(60 * 60)
                ),
                FocusInterval(
                    kind: .work,
                    start: start.addingTimeInterval(60 * 60),
                    end: start.addingTimeInterval(110 * 60)
                ),
            ]
        )
        let coordinator = SessionCoordinator(now: { clock.now })
        try await coordinator.configure(plan)
        _ = try await coordinator.handle(SessionRequest(requestID: UUID(), command: .start))
        let activeBreak = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .workIntervalElapsed)
        ).snapshot

        clock.now = try #require(activeBreak.deadline).addingTimeInterval(-0.001)
        await #expect(throws: SessionTransitionError.self) {
            try await coordinator.handle(
                SessionRequest(
                    requestID: UUID(),
                    command: .completeBreak,
                    issuedAt: activeBreak.deadline?.addingTimeInterval(60 * 60)
                )
            )
        }
        #expect(await coordinator.snapshot.phase == .overlayActive)

        clock.now = try #require(activeBreak.deadline)
        let resumed = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .completeBreak)
        ).snapshot
        #expect(resumed.phase == .working)
        #expect(resumed.deadline == clock.now.addingTimeInterval(50 * 60))
    }

    @Test("late lunch return consumes an adjacent reading break before work resumes")
    func catchesUpAfterLateLunchReturn() async throws {
        let start = Date(timeIntervalSince1970: 1_721_488_400)
        let clock = TestClock(start)
        let plan = try DailySessionPlan(
            localDay: "2026-07-20",
            intervals: [
                FocusInterval(kind: .work, start: start, end: start.addingTimeInterval(50 * 60)),
                FocusInterval(
                    kind: .lunch,
                    start: start.addingTimeInterval(50 * 60),
                    end: start.addingTimeInterval(95 * 60)
                ),
                FocusInterval(
                    kind: .readingBreak,
                    start: start.addingTimeInterval(95 * 60),
                    end: start.addingTimeInterval(120 * 60)
                ),
                FocusInterval(
                    kind: .work,
                    start: start.addingTimeInterval(120 * 60),
                    end: start.addingTimeInterval(170 * 60)
                ),
            ]
        )
        let coordinator = SessionCoordinator(now: { clock.now })
        try await coordinator.configure(plan)
        _ = try await coordinator.handle(SessionRequest(requestID: UUID(), command: .start))
        let lunch = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .workIntervalElapsed)
        ).snapshot

        clock.now = try #require(lunch.deadline).addingTimeInterval(30 * 60)
        let resumed = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .completeBreak)
        ).snapshot

        #expect(resumed.phase == .working)
        #expect(resumed.currentIntervalIndex == 3)
        #expect(resumed.currentInterval?.kind == .work)
        #expect(resumed.deadline == clock.now.addingTimeInterval(50 * 60))
    }

    @Test("a small lunch overrun reduces the adjacent reading break")
    func reducesReadingBreakAfterSmallLunchOverrun() async throws {
        let start = Date(timeIntervalSince1970: 1_721_488_400)
        let clock = TestClock(start)
        let plan = try DailySessionPlan(
            localDay: "2026-07-20",
            intervals: [
                FocusInterval(kind: .work, start: start, end: start.addingTimeInterval(50 * 60)),
                FocusInterval(
                    kind: .lunch,
                    start: start.addingTimeInterval(50 * 60),
                    end: start.addingTimeInterval(95 * 60)
                ),
                FocusInterval(
                    kind: .readingBreak,
                    start: start.addingTimeInterval(95 * 60),
                    end: start.addingTimeInterval(120 * 60)
                ),
                FocusInterval(
                    kind: .work,
                    start: start.addingTimeInterval(120 * 60),
                    end: start.addingTimeInterval(170 * 60)
                ),
            ]
        )
        let coordinator = SessionCoordinator(now: { clock.now })
        try await coordinator.configure(plan)
        _ = try await coordinator.handle(SessionRequest(requestID: UUID(), command: .start))
        let lunch = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .workIntervalElapsed)
        ).snapshot

        clock.now = try #require(lunch.deadline).addingTimeInterval(10 * 60)
        let reading = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .completeBreak)
        ).snapshot

        #expect(reading.phase == .overlayActive)
        #expect(reading.currentIntervalIndex == 2)
        #expect(reading.currentInterval?.kind == .readingBreak)
        #expect(reading.deadline == clock.now.addingTimeInterval(15 * 60))
    }

    @Test("cannot replace a daily plan while a session is active")
    func rejectsActiveReconfiguration() async throws {
        let start = Date(timeIntervalSince1970: 1_721_488_400)
        let plan = try DailySessionPlan(
            localDay: "2026-07-20",
            intervals: [
                FocusInterval(kind: .work, start: start, end: start.addingTimeInterval(50 * 60)),
            ]
        )
        let coordinator = SessionCoordinator()
        try await coordinator.configure(plan)
        _ = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .start)
        )

        await #expect(throws: SessionPlanError.sessionAlreadyActive) {
            try await coordinator.configure(plan)
        }
    }

    @Test("concurrent start requests share one global session")
    func deduplicatesConcurrentStarts() async throws {
        let coordinator = SessionCoordinator()

        let snapshots = try await withThrowingTaskGroup(
            of: SessionSnapshot.self,
            returning: [SessionSnapshot].self
        ) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await coordinator.handle(
                        SessionRequest(requestID: UUID(), command: .start)
                    ).snapshot
                }
            }

            var results: [SessionSnapshot] = []
            for try await snapshot in group {
                results.append(snapshot)
            }
            return results
        }

        let sessionIDs = Set(snapshots.compactMap(\.sessionID))
        #expect(sessionIDs.count == 1)
        #expect(await coordinator.snapshot.revision == 1)
    }

    @Test("a retried request returns its original result without another transition")
    func deduplicatesRequestRetries() async throws {
        let coordinator = SessionCoordinator()
        _ = try await coordinator.handle(
            SessionRequest(requestID: UUID(), command: .start)
        )
        let pauseRequest = SessionRequest(requestID: UUID(), command: .pause)

        let first = try await coordinator.handle(pauseRequest)
        let retried = try await coordinator.handle(pauseRequest)

        #expect(first == retried)
        #expect(await coordinator.snapshot.revision == 2)
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}
