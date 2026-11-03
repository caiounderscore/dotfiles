import Foundation

public enum SessionPhase: String, Codable, Equatable, Sendable {
    case inactive
    case working
    case breakDue
    case overlayActive
    case paused
    case completed
}

public enum SessionCommand: String, Codable, Equatable, Sendable {
    case configure
    case start
    case status
    case pause
    case resume
    case snooze
    case skip
    case stop
    case workIntervalElapsed
    case reminderEscalated
    case completeBreak
}

public struct SessionSnapshot: Codable, Equatable, Sendable {
    public let sessionID: UUID?
    public let phase: SessionPhase
    public let revision: Int
    public let firstDismissalUsed: Bool
    public let resumePhase: SessionPhase?
    public let currentInterval: FocusInterval?
    public let currentIntervalIndex: Int?
    public let deadline: Date?
    public let pausedRemaining: TimeInterval?

    public init(
        sessionID: UUID? = nil,
        phase: SessionPhase = .inactive,
        revision: Int = 0,
        firstDismissalUsed: Bool = false,
        resumePhase: SessionPhase? = nil,
        currentInterval: FocusInterval? = nil,
        currentIntervalIndex: Int? = nil,
        deadline: Date? = nil,
        pausedRemaining: TimeInterval? = nil
    ) {
        self.sessionID = sessionID
        self.phase = phase
        self.revision = revision
        self.firstDismissalUsed = firstDismissalUsed
        self.resumePhase = resumePhase
        self.currentInterval = currentInterval
        self.currentIntervalIndex = currentIntervalIndex
        self.deadline = deadline
        self.pausedRemaining = pausedRemaining
    }
}

public enum SessionTransitionError: Error, Equatable {
    case invalidTransition
    case breakStillActive(remaining: TimeInterval)
}

public struct SessionStateMachine: Sendable {
    private enum ResumePhaseUpdate {
        case preserve
        case set(SessionPhase?)
    }

    public private(set) var snapshot: SessionSnapshot

    public init(snapshot: SessionSnapshot = SessionSnapshot()) {
        self.snapshot = snapshot
    }

    @discardableResult
    public mutating func apply(_ command: SessionCommand) throws -> SessionSnapshot {
        if command == .status {
            return snapshot
        }

        switch (snapshot.phase, command) {
        case (.inactive, .start), (.completed, .start):
            update(
                sessionID: UUID(),
                phase: .working,
                firstDismissalUsed: false,
                resumePhase: .set(nil)
            )

        case (.working, .start),
             (.breakDue, .start),
             (.overlayActive, .start),
             (.paused, .start):
            return snapshot

        case (.working, .workIntervalElapsed):
            update(phase: .overlayActive, firstDismissalUsed: false)

        case (.breakDue, .reminderEscalated):
            update(phase: .overlayActive)

        case (.overlayActive, .snooze) where snapshot.firstDismissalUsed == false:
            update(phase: .breakDue, firstDismissalUsed: true)

        case (.breakDue, .skip) where snapshot.firstDismissalUsed:
            update(phase: .working, firstDismissalUsed: false)

        case (.overlayActive, .skip) where snapshot.firstDismissalUsed:
            update(phase: .working, firstDismissalUsed: false)

        case (.breakDue, .completeBreak), (.overlayActive, .completeBreak):
            update(phase: .working, firstDismissalUsed: false)

        case (.working, .pause):
            update(phase: .paused, resumePhase: .set(snapshot.phase))

        case (.paused, .resume):
            guard let resumePhase = snapshot.resumePhase else {
                throw SessionTransitionError.invalidTransition
            }
            update(phase: resumePhase, resumePhase: .set(nil))

        case (.working, .stop), (.breakDue, .stop),
             (.overlayActive, .stop), (.paused, .stop):
            update(phase: .completed, firstDismissalUsed: false, resumePhase: .set(nil))

        default:
            throw SessionTransitionError.invalidTransition
        }

        return snapshot
    }

    private mutating func update(
        sessionID: UUID? = nil,
        phase: SessionPhase,
        firstDismissalUsed: Bool? = nil,
        resumePhase: ResumePhaseUpdate = .preserve
    ) {
        let nextResumePhase: SessionPhase?
        switch resumePhase {
        case .preserve:
            nextResumePhase = snapshot.resumePhase
        case let .set(phase):
            nextResumePhase = phase
        }

        snapshot = SessionSnapshot(
            sessionID: sessionID ?? snapshot.sessionID,
            phase: phase,
            revision: snapshot.revision + 1,
            firstDismissalUsed: firstDismissalUsed ?? snapshot.firstDismissalUsed,
            resumePhase: nextResumePhase,
            currentInterval: snapshot.currentInterval,
            currentIntervalIndex: snapshot.currentIntervalIndex,
            deadline: snapshot.deadline,
            pausedRemaining: snapshot.pausedRemaining
        )
    }

    mutating func setRuntime(
        interval: FocusInterval?,
        index: Int?,
        deadline: Date?,
        pausedRemaining: TimeInterval? = nil
    ) {
        snapshot = SessionSnapshot(
            sessionID: snapshot.sessionID,
            phase: snapshot.phase,
            revision: snapshot.revision,
            firstDismissalUsed: snapshot.firstDismissalUsed,
            resumePhase: snapshot.resumePhase,
            currentInterval: interval,
            currentIntervalIndex: index,
            deadline: deadline,
            pausedRemaining: pausedRemaining
        )
    }
}

public enum SessionPlanError: Error, Equatable {
    case invalidPlan
    case planAlreadyConfigured
    case planRequired
    case sessionAlreadyActive
}

public struct DailySessionPlan: Codable, Equatable, Sendable {
    public let localDay: String
    public let intervals: [FocusInterval]
    public let selectedCalendarIdentifier: String?
    public let calendarWritesConfirmed: Bool

    public init(
        localDay: String,
        intervals: [FocusInterval],
        selectedCalendarIdentifier: String? = nil,
        calendarWritesConfirmed: Bool = false
    ) throws {
        guard localDay.isEmpty == false,
              intervals.isEmpty == false,
              intervals[0].kind == .work,
              intervals.allSatisfy({ $0.start < $0.end }) else {
            throw SessionPlanError.invalidPlan
        }

        for (previous, next) in zip(intervals, intervals.dropFirst()) {
            guard previous.end <= next.start else {
                throw SessionPlanError.invalidPlan
            }
        }

        self.localDay = localDay
        self.intervals = intervals
        self.selectedCalendarIdentifier = selectedCalendarIdentifier
        self.calendarWritesConfirmed = calendarWritesConfirmed
    }
}

public struct SessionRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let command: SessionCommand
    public let dailyPlan: DailySessionPlan?
    public let issuedAt: Date?

    public init(
        requestID: UUID,
        command: SessionCommand,
        dailyPlan: DailySessionPlan? = nil,
        issuedAt: Date? = Date()
    ) {
        self.requestID = requestID
        self.command = command
        self.dailyPlan = dailyPlan
        self.issuedAt = issuedAt
    }
}

public struct SessionResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let snapshot: SessionSnapshot

    public init(requestID: UUID, snapshot: SessionSnapshot) {
        self.requestID = requestID
        self.snapshot = snapshot
    }
}

public struct SessionCoordinatorState: Codable, Equatable, Sendable {
    public let snapshot: SessionSnapshot
    public let completedResponses: [SessionResponse]
    public let dailyPlan: DailySessionPlan?

    public init(
        snapshot: SessionSnapshot = SessionSnapshot(),
        completedResponses: [SessionResponse] = [],
        dailyPlan: DailySessionPlan? = nil
    ) {
        self.snapshot = snapshot
        self.completedResponses = completedResponses
        self.dailyPlan = dailyPlan
    }
}

public actor SessionCoordinator {
    private var machine: SessionStateMachine
    private var completedRequests: [UUID: SessionResponse]
    private var dailyPlan: DailySessionPlan?
    private let requiresDailyPlan: Bool
    private let now: @Sendable () -> Date

    public init(
        snapshot: SessionSnapshot = SessionSnapshot(),
        requiresDailyPlan: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        machine = SessionStateMachine(snapshot: snapshot)
        completedRequests = [:]
        dailyPlan = nil
        self.requiresDailyPlan = requiresDailyPlan
        self.now = now
    }

    public init(
        state: SessionCoordinatorState,
        requiresDailyPlan: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        machine = SessionStateMachine(snapshot: state.snapshot)
        completedRequests = Dictionary(
            uniqueKeysWithValues: state.completedResponses.map { ($0.requestID, $0) }
        )
        dailyPlan = state.dailyPlan
        self.requiresDailyPlan = requiresDailyPlan
        self.now = now
    }

    public var snapshot: SessionSnapshot {
        machine.snapshot
    }

    public func exportState() -> SessionCoordinatorState {
        SessionCoordinatorState(
            snapshot: machine.snapshot,
            completedResponses: completedRequests.values.sorted {
                $0.requestID.uuidString < $1.requestID.uuidString
            },
            dailyPlan: dailyPlan
        )
    }

    public func configure(_ plan: DailySessionPlan) throws {
        guard machine.snapshot.phase == .inactive || machine.snapshot.phase == .completed else {
            throw SessionPlanError.sessionAlreadyActive
        }
        if machine.snapshot.phase == .inactive, dailyPlan != nil {
            throw SessionPlanError.planAlreadyConfigured
        }
        dailyPlan = plan
        machine.setRuntime(interval: nil, index: nil, deadline: nil)
    }

    public func restore(_ state: SessionCoordinatorState) throws {
        guard machine.snapshot.phase == .inactive else {
            throw SessionPlanError.sessionAlreadyActive
        }
        machine = SessionStateMachine(snapshot: state.snapshot)
        completedRequests = Dictionary(
            uniqueKeysWithValues: state.completedResponses.map { ($0.requestID, $0) }
        )
        dailyPlan = state.dailyPlan
    }

    public func handle(_ request: SessionRequest) throws -> SessionResponse {
        if let completed = completedRequests[request.requestID] {
            return completed
        }

        if request.command == .configure {
            guard let plan = request.dailyPlan else {
                throw SessionPlanError.invalidPlan
            }
            try configure(plan)
            let response = SessionResponse(
                requestID: request.requestID,
                snapshot: machine.snapshot
            )
            completedRequests[request.requestID] = response
            return response
        }

        let previous = machine.snapshot
        let commandTime = now()
        if request.command == .start,
           requiresDailyPlan,
           dailyPlan == nil {
            throw SessionPlanError.planRequired
        }
        if request.command == .completeBreak,
           [.breakDue, .overlayActive].contains(previous.phase) {
            let remaining = previous.deadline.map {
                max(0, $0.timeIntervalSince(commandTime))
            } ?? previous.currentInterval?.duration ?? 0
            guard remaining == 0 else {
                throw SessionTransitionError.breakStillActive(remaining: remaining)
            }
        }
        let advancesPlan = [
            SessionCommand.workIntervalElapsed,
            .completeBreak,
            .skip,
        ].contains(request.command)
        let breakOverrun: TimeInterval
        if request.command == .completeBreak, let deadline = previous.deadline {
            breakOverrun = max(0, commandTime.timeIntervalSince(deadline))
        } else {
            breakOverrun = 0
        }
        let plannedAdvance = advancesPlan
            ? nextRuntimeInterval(
                after: previous.currentIntervalIndex,
                carryingBreakOverrun: breakOverrun
            )
            : nil

        if advancesPlan, dailyPlan != nil, plannedAdvance == nil {
            _ = try machine.apply(.stop)
            machine.setRuntime(interval: nil, index: nil, deadline: nil)
        } else {
            _ = try machine.apply(request.command)
            updateRuntime(
                after: request.command,
                previous: previous,
                at: commandTime,
                plannedAdvance: plannedAdvance
            )
        }

        let currentSnapshot = machine.snapshot
        let response = SessionResponse(requestID: request.requestID, snapshot: currentSnapshot)
        if request.command != .status {
            completedRequests[request.requestID] = response
        }
        return response
    }

    private func nextRuntimeInterval(
        after index: Int?,
        carryingBreakOverrun initialOverrun: TimeInterval
    ) -> (index: Int, interval: FocusInterval, duration: TimeInterval)? {
        guard let plan = dailyPlan, let index else { return nil }
        var breakOverrun = initialOverrun

        for nextIndex in plan.intervals.indices.dropFirst(index + 1) {
            let interval = plan.intervals[nextIndex]
            guard interval.kind != .work, breakOverrun > 0 else {
                return (nextIndex, interval, interval.duration)
            }
            guard breakOverrun >= interval.duration else {
                return (nextIndex, interval, interval.duration - breakOverrun)
            }
            breakOverrun -= interval.duration
        }
        return nil
    }

    private func updateRuntime(
        after command: SessionCommand,
        previous: SessionSnapshot,
        at commandTime: Date,
        plannedAdvance: (index: Int, interval: FocusInterval, duration: TimeInterval)?
    ) {
        switch command {
        case .start where previous.phase == .inactive || previous.phase == .completed:
            guard let first = dailyPlan?.intervals.first else { return }
            machine.setRuntime(
                interval: first,
                index: 0,
                deadline: commandTime.addingTimeInterval(first.duration)
            )
        case .workIntervalElapsed, .completeBreak, .skip:
            guard let plannedAdvance else { return }
            let index = plannedAdvance.index
            let interval = plannedAdvance.interval
            if (command == .completeBreak || command == .skip), interval.kind != .work {
                _ = try? machine.apply(.workIntervalElapsed)
            }
            machine.setRuntime(
                interval: interval,
                index: index,
                deadline: commandTime.addingTimeInterval(plannedAdvance.duration)
            )
        case .reminderEscalated:
            guard let interval = previous.currentInterval else { return }
            machine.setRuntime(
                interval: interval,
                index: previous.currentIntervalIndex,
                deadline: commandTime.addingTimeInterval(interval.duration)
            )
        case .snooze:
            machine.setRuntime(
                interval: previous.currentInterval,
                index: previous.currentIntervalIndex,
                deadline: nil
            )
        case .pause:
            let remaining = previous.deadline.map {
                max(0, $0.timeIntervalSince(commandTime))
            }
            machine.setRuntime(
                interval: previous.currentInterval,
                index: previous.currentIntervalIndex,
                deadline: nil,
                pausedRemaining: remaining
            )
        case .resume:
            machine.setRuntime(
                interval: previous.currentInterval,
                index: previous.currentIntervalIndex,
                deadline: previous.pausedRemaining.map(commandTime.addingTimeInterval),
                pausedRemaining: nil
            )
        case .stop:
            machine.setRuntime(interval: nil, index: nil, deadline: nil)
        default:
            break
        }
    }
}
