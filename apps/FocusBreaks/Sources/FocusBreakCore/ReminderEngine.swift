import Foundation

public enum BreakReminderKind: String, Codable, Equatable, Sendable {
    case shortBreak
    case readingBreak
    case lunch
}

public struct BreakPresentation: Codable, Equatable, Sendable {
    public let kind: BreakReminderKind
    public let title: String
    public let guidance: String
    public let duration: TimeInterval
    public let completionLabel: String
    public let emergencyDismissLabel: String
    public let accessibilitySummary: String
    public let deadline: Date?

    public init(
        kind: BreakReminderKind,
        title: String,
        guidance: String,
        duration: TimeInterval,
        completionLabel: String,
        emergencyDismissLabel: String,
        accessibilitySummary: String,
        deadline: Date? = nil
    ) {
        self.kind = kind
        self.title = title
        self.guidance = guidance
        self.duration = duration
        self.completionLabel = completionLabel
        self.emergencyDismissLabel = emergencyDismissLabel
        self.accessibilitySummary = accessibilitySummary
        self.deadline = deadline
    }

    func withDeadline(_ deadline: Date) -> BreakPresentation {
        BreakPresentation(
            kind: kind,
            title: title,
            guidance: guidance,
            duration: duration,
            completionLabel: completionLabel,
            emergencyDismissLabel: emergencyDismissLabel,
            accessibilitySummary: accessibilitySummary,
            deadline: deadline
        )
    }
}

public enum ReminderEffect: Equatable, Sendable {
    case deliverNotification(BreakPresentation)
    case showOverlay(BreakPresentation)
    case hideOverlay
    case skipped(BreakReminderKind)
    case returnToWorkNotification
    case sessionCompleteNotification
}

public enum ReminderEngineError: Error, Equatable {
    case breakAlreadyActive
    case invalidDuration
}

public struct ReminderEngine: Sendable {
    private enum State: Sendable {
        case idle
        case notified(BreakPresentation, escalationAt: Date, firstDismissalUsed: Bool)
        case overlay(BreakPresentation, firstDismissalUsed: Bool)
        case snoozed(BreakPresentation, escalationAt: Date)
    }

    private var state: State = .idle

    public init() {}

    public var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    public mutating func beginBreak(
        _ kind: BreakReminderKind,
        duration: TimeInterval,
        at now: Date,
        deadline: Date? = nil
    ) throws -> [ReminderEffect] {
        guard isActive == false else {
            throw ReminderEngineError.breakAlreadyActive
        }
        guard duration > 0 else {
            throw ReminderEngineError.invalidDuration
        }

        let presentation = Self.presentation(for: kind, duration: duration)
            .withDeadline(deadline ?? now.addingTimeInterval(duration))
        state = .overlay(presentation, firstDismissalUsed: false)
        return [.showOverlay(presentation), .deliverNotification(presentation)]
    }

    public mutating func advance(to now: Date) -> [ReminderEffect] {
        switch state {
        case let .notified(presentation, escalationAt, firstDismissalUsed)
            where now >= escalationAt:
            let active = presentation.withDeadline(now.addingTimeInterval(presentation.duration))
            state = .overlay(active, firstDismissalUsed: firstDismissalUsed)
            return [.showOverlay(active)]

        case let .snoozed(presentation, escalationAt) where now >= escalationAt:
            let active = presentation.withDeadline(now.addingTimeInterval(presentation.duration))
            state = .overlay(active, firstDismissalUsed: true)
            return [.showOverlay(active)]

        default:
            return []
        }
    }

    public mutating func emergencyDismiss(at now: Date) -> [ReminderEffect] {
        guard case let .overlay(presentation, firstDismissalUsed) = state else {
            return []
        }

        if firstDismissalUsed == false {
            state = .snoozed(
                presentation,
                escalationAt: now.addingTimeInterval(5 * 60)
            )
            return [.hideOverlay]
        }

        state = .idle
        return [
            .hideOverlay,
            .skipped(presentation.kind),
            .returnToWorkNotification,
        ]
    }

    public mutating func complete() -> [ReminderEffect] {
        let overlayVisible: Bool
        switch state {
        case .overlay:
            overlayVisible = true
        case .idle:
            return []
        default:
            overlayVisible = false
        }

        state = .idle
        return overlayVisible
            ? [.hideOverlay, .returnToWorkNotification]
            : [.returnToWorkNotification]
    }

    public mutating func cancel() -> [ReminderEffect] {
        guard isActive else { return [] }
        let overlayVisible: Bool
        if case .overlay = state {
            overlayVisible = true
        } else {
            overlayVisible = false
        }
        state = .idle
        return overlayVisible ? [.hideOverlay] : []
    }

    private static func presentation(
        for kind: BreakReminderKind,
        duration: TimeInterval
    ) -> BreakPresentation {
        let title: String
        let guidance: String
        switch kind {
        case .shortBreak:
            title = "Short break"
            guidance = "Drink water, move, and look into the distance."
        case .readingBreak:
            title = "Reading break"
            guidance = "Step away from the desk and read your book."
        case .lunch:
            title = "Lunch break"
            guidance = "Eat lunch and step away from your desk."
        }

        return BreakPresentation(
            kind: kind,
            title: title,
            guidance: guidance,
            duration: duration,
            completionLabel: "Complete break",
            emergencyDismissLabel: "Emergency dismiss",
            accessibilitySummary: "\(title). \(guidance)"
        )
    }
}

public struct OverlayDisplayChanges: Equatable, Sendable {
    public let created: [String]
    public let removed: [String]
}

public struct OverlayDisplayRegistry: Sendable {
    public private(set) var activeDisplayIDs: [String] = []

    public init() {}

    public mutating func present(on displayIDs: [String]) -> OverlayDisplayChanges {
        reconcile(with: displayIDs)
    }

    public mutating func reconcile(with displayIDs: [String]) -> OverlayDisplayChanges {
        let previous = Set(activeDisplayIDs)
        let current = Set(displayIDs)
        let changes = OverlayDisplayChanges(
            created: current.subtracting(previous).sorted(),
            removed: previous.subtracting(current).sorted()
        )
        activeDisplayIDs = current.sorted()
        return changes
    }

    public mutating func dismiss() -> OverlayDisplayChanges {
        let changes = OverlayDisplayChanges(created: [], removed: activeDisplayIDs.sorted())
        activeDisplayIDs = []
        return changes
    }
}
