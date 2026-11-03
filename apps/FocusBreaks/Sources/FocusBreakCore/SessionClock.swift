import Foundation

public struct FocusEndingWarning: Equatable, Sendable {
    public let identifier: String
    public let fireDate: Date

    public init(identifier: String, fireDate: Date) {
        self.identifier = identifier
        self.fireDate = fireDate
    }
}

public enum SessionClock {
    public static let focusEndingWarningLeadTime: TimeInterval = 5 * 60

    public static func didCompleteSession(
        from previous: SessionSnapshot,
        to current: SessionSnapshot
    ) -> Bool {
        previous.phase == .working
            && previous.currentInterval?.kind == .work
            && current.phase == .completed
            && current.currentInterval == nil
    }

    public static func didCompleteSchedule(
        from previous: SessionSnapshot,
        to current: SessionSnapshot,
        after command: SessionCommand
    ) -> Bool {
        [.workIntervalElapsed, .completeBreak, .skip].contains(command)
            && ![.inactive, .completed].contains(previous.phase)
            && current.phase == .completed
            && current.currentInterval == nil
    }

    public static func dueCommand(
        for snapshot: SessionSnapshot,
        at now: Date
    ) -> SessionCommand? {
        guard snapshot.phase == .working,
              let interval = snapshot.currentInterval,
              interval.kind == .work,
              let deadline = snapshot.deadline,
              now >= deadline else {
            return nil
        }
        return .workIntervalElapsed
    }

    public static func remaining(
        for snapshot: SessionSnapshot,
        at now: Date
    ) -> TimeInterval? {
        guard snapshot.currentInterval != nil else { return nil }
        if snapshot.phase == .paused {
            return snapshot.pausedRemaining.map { max(0, $0) }
        }
        return snapshot.deadline.map { max(0, $0.timeIntervalSince(now)) }
    }

    public static func focusEndingWarning(
        for snapshot: SessionSnapshot,
        at now: Date,
        leadTime: TimeInterval = focusEndingWarningLeadTime
    ) -> FocusEndingWarning? {
        guard snapshot.phase == .working,
              snapshot.currentInterval?.kind == .work,
              let sessionID = snapshot.sessionID,
              let intervalIndex = snapshot.currentIntervalIndex,
              let deadline = snapshot.deadline,
              (snapshot.currentInterval?.duration ?? 0) > leadTime else {
            return nil
        }

        let fireDate = deadline.addingTimeInterval(-leadTime)
        guard fireDate > now else { return nil }
        return FocusEndingWarning(
            identifier: "focus-breaks.work-ending.\(sessionID.uuidString).\(intervalIndex)",
            fireDate: fireDate
        )
    }

    public static func focusEndingWarningIdentifier(
        for snapshot: SessionSnapshot
    ) -> String? {
        guard let sessionID = snapshot.sessionID,
              let intervalIndex = snapshot.currentIntervalIndex,
              snapshot.currentInterval?.kind == .work else {
            return nil
        }
        return "focus-breaks.work-ending.\(sessionID.uuidString).\(intervalIndex)"
    }
}
