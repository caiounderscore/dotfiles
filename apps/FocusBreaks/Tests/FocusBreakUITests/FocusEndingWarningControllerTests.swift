import FocusBreakCore
import Foundation
import Testing
@testable import FocusBreakUI

@MainActor
struct FocusEndingWarningControllerTests {
    @Test("schedules once and replaces the warning after pause and resume")
    func reconcilesWorkDeadlineChanges() async throws {
        let start = Date(timeIntervalSince1970: 100)
        let poster = FakeFocusEndingWarningPoster()
        let controller = FocusEndingWarningController(poster: poster)
        let working = fixtureSnapshot(start: start)

        try await controller.reconcile(working, at: start)
        try await controller.reconcile(working, at: start.addingTimeInterval(1))
        #expect(poster.scheduled.count == 1)

        let paused = fixtureSnapshot(start: start, phase: .paused, deadline: nil)
        try await controller.reconcile(paused, at: start.addingTimeInterval(10 * 60))
        #expect(poster.cancelled == [poster.scheduled[0].identifier])

        let shiftedDeadline = start.addingTimeInterval(60 * 60)
        let resumed = fixtureSnapshot(start: start, deadline: shiftedDeadline)
        try await controller.reconcile(resumed, at: start.addingTimeInterval(10 * 60))
        #expect(poster.scheduled.count == 2)
        #expect(poster.scheduled[1].fireDate == shiftedDeadline.addingTimeInterval(-5 * 60))
    }

    @Test("recovery after the warning boundary cancels a stale pending request")
    func cancelsLateRecoveryWarning() async throws {
        let start = Date(timeIntervalSince1970: 100)
        let poster = FakeFocusEndingWarningPoster()
        let controller = FocusEndingWarningController(poster: poster)
        let recovered = fixtureSnapshot(start: start)

        try await controller.reconcile(
            recovered,
            at: start.addingTimeInterval(46 * 60)
        )

        #expect(poster.scheduled.isEmpty)
        #expect(poster.cancelled == [
            try #require(SessionClock.focusEndingWarningIdentifier(for: recovered)),
        ])
    }

    @Test("a scheduling failure does not claim that a warning is active")
    func preservesFailureState() async {
        let start = Date(timeIntervalSince1970: 100)
        let poster = FakeFocusEndingWarningPoster(shouldFail: true)
        let controller = FocusEndingWarningController(poster: poster)

        await #expect(throws: FocusEndingWarningTestError.failed) {
            try await controller.reconcile(fixtureSnapshot(start: start), at: start)
        }
        #expect(controller.scheduledWarning == nil)
    }

    private func fixtureSnapshot(
        start: Date,
        phase: SessionPhase = .working,
        deadline: Date? = nil
    ) -> SessionSnapshot {
        let interval = FocusInterval(
            kind: .work,
            start: start,
            end: start.addingTimeInterval(50 * 60)
        )
        return SessionSnapshot(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            phase: phase,
            revision: 1,
            currentInterval: interval,
            currentIntervalIndex: 0,
            deadline: phase == .paused ? nil : (deadline ?? interval.end)
        )
    }
}

private enum FocusEndingWarningTestError: Error {
    case failed
}

@MainActor
private final class FakeFocusEndingWarningPoster: FocusEndingWarningPosting {
    private(set) var scheduled: [FocusEndingWarning] = []
    private(set) var cancelled: [String] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func scheduleFocusEndingWarning(_ warning: FocusEndingWarning) async throws {
        if shouldFail {
            throw FocusEndingWarningTestError.failed
        }
        scheduled.append(warning)
    }

    func cancelFocusEndingWarning(identifier: String) {
        cancelled.append(identifier)
    }
}
