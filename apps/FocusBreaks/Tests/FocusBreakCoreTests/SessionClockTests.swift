import Foundation
import Testing
@testable import FocusBreakCore

struct SessionClockTests {
    @Test("detects completion when the final work interval expires")
    func detectsFinalWorkCompletion() {
        let interval = FocusInterval(
            kind: .work,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 5 * 60)
        )
        let previous = SessionSnapshot(
            sessionID: UUID(),
            phase: .working,
            revision: 1,
            currentInterval: interval,
            currentIntervalIndex: 0,
            deadline: interval.end
        )
        let completed = SessionSnapshot(
            sessionID: previous.sessionID,
            phase: .completed,
            revision: 2
        )

        #expect(SessionClock.didCompleteSession(from: previous, to: completed))
        #expect(SessionClock.didCompleteSession(from: previous, to: previous) == false)
        #expect(SessionClock.didCompleteSchedule(
            from: previous,
            to: completed,
            after: .workIntervalElapsed
        ))
        #expect(SessionClock.didCompleteSchedule(
            from: previous,
            to: completed,
            after: .stop
        ) == false)
    }

    @Test("detects schedule completion after the final break")
    func detectsFinalBreakCompletion() {
        let interval = FocusInterval(
            kind: .readingBreak,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 30 * 60)
        )
        let previous = SessionSnapshot(
            sessionID: UUID(),
            phase: .overlayActive,
            revision: 3,
            currentInterval: interval,
            currentIntervalIndex: 2,
            deadline: interval.end
        )
        let completed = SessionSnapshot(
            sessionID: previous.sessionID,
            phase: .completed,
            revision: 4
        )

        #expect(SessionClock.didCompleteSchedule(
            from: previous,
            to: completed,
            after: .completeBreak
        ))
    }

    @Test("work deadline advances only the authoritative active interval")
    func advancesAtDeadline() {
        let start = Date(timeIntervalSince1970: 100)
        let interval = FocusInterval(
            kind: .work,
            start: start,
            end: start.addingTimeInterval(50 * 60)
        )
        let working = SessionSnapshot(
            sessionID: UUID(),
            phase: .working,
            revision: 1,
            currentInterval: interval,
            currentIntervalIndex: 0,
            deadline: interval.end.addingTimeInterval(30)
        )

        #expect(SessionClock.dueCommand(for: working, at: interval.end) == nil)
        #expect(SessionClock.dueCommand(
            for: working,
            at: interval.end.addingTimeInterval(30)
        ) == .workIntervalElapsed)
    }

    @Test("paused sessions do not advance and remaining time is bounded")
    func pausesClock() {
        let start = Date(timeIntervalSince1970: 100)
        let interval = FocusInterval(
            kind: .work,
            start: start,
            end: start.addingTimeInterval(50 * 60)
        )
        let paused = SessionSnapshot(
            sessionID: UUID(),
            phase: .paused,
            revision: 2,
            currentInterval: interval,
            currentIntervalIndex: 0,
            pausedRemaining: 0
        )

        #expect(SessionClock.dueCommand(for: paused, at: interval.end) == nil)
        #expect(SessionClock.remaining(for: paused, at: interval.end.addingTimeInterval(10)) == 0)
    }

    @Test("schedules a stable warning five minutes before a work deadline")
    func schedulesFocusEndingWarning() throws {
        let start = Date(timeIntervalSince1970: 100)
        let sessionID = UUID()
        let interval = FocusInterval(
            kind: .work,
            start: start,
            end: start.addingTimeInterval(50 * 60)
        )
        let snapshot = SessionSnapshot(
            sessionID: sessionID,
            phase: .working,
            revision: 1,
            currentInterval: interval,
            currentIntervalIndex: 2,
            deadline: interval.end
        )

        let warning = try #require(
            SessionClock.focusEndingWarning(for: snapshot, at: start)
        )

        #expect(warning.fireDate == start.addingTimeInterval(45 * 60))
        #expect(warning.identifier == "focus-breaks.work-ending.\(sessionID.uuidString).2")
    }

    @Test("does not schedule short or late focus warnings")
    func skipsIneligibleFocusEndingWarnings() {
        let start = Date(timeIntervalSince1970: 100)
        let fiveMinuteInterval = FocusInterval(
            kind: .work,
            start: start,
            end: start.addingTimeInterval(5 * 60)
        )
        let shortSnapshot = SessionSnapshot(
            sessionID: UUID(),
            phase: .working,
            revision: 1,
            currentInterval: fiveMinuteInterval,
            currentIntervalIndex: 0,
            deadline: fiveMinuteInterval.end
        )
        let longInterval = FocusInterval(
            kind: .work,
            start: start,
            end: start.addingTimeInterval(50 * 60)
        )
        let recoveredAfterWarning = SessionSnapshot(
            sessionID: UUID(),
            phase: .working,
            revision: 1,
            currentInterval: longInterval,
            currentIntervalIndex: 0,
            deadline: longInterval.end
        )

        #expect(SessionClock.focusEndingWarning(for: shortSnapshot, at: start) == nil)
        #expect(SessionClock.focusEndingWarning(
            for: recoveredAfterWarning,
            at: start.addingTimeInterval(46 * 60)
        ) == nil)
    }
}
