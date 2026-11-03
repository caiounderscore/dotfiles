import Foundation

public struct FocusInterval: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case work
        case shortBreak
        case readingBreak
        case lunch
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    public init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

public struct ScheduleConfiguration: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let readingBreakMinutes: Int
    public let lunchWindow: DateInterval?
    public let busyIntervals: [BusyInterval]

    public init(
        start: Date,
        end: Date,
        readingBreakMinutes: Int,
        lunchWindow: DateInterval? = nil,
        busyIntervals: [BusyInterval] = []
    ) {
        self.start = start
        self.end = end
        self.readingBreakMinutes = readingBreakMinutes
        self.lunchWindow = lunchWindow
        self.busyIntervals = busyIntervals
    }
}

public enum SchedulePlanningError: Error, Equatable {
    case invalidLunchWindow
    case invalidReadingBreakDuration
    case lunchCannotFit
    case protectedBreakExceedsSession
    case sessionTooShort
}

public struct BusyInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let isBusy: Bool

    public init(start: Date, end: Date, isBusy: Bool) {
        self.start = start
        self.end = end
        self.isBusy = isBusy
    }
}

public struct SchedulePreview: Equatable, Sendable {
    public let intervals: [FocusInterval]

    public init(intervals: [FocusInterval]) {
        self.intervals = intervals
    }

    public var calendarWrites: [FocusInterval] {
        intervals.filter { interval in
            interval.kind == .readingBreak || interval.kind == .lunch
        }
    }
}

public struct SchedulePlanner: Sendable {
    public init() {}

    public func plan(_ configuration: ScheduleConfiguration) throws -> [FocusInterval] {
        let sessionDuration = configuration.end.timeIntervalSince(configuration.start)
        guard sessionDuration > 0 else {
            throw SchedulePlanningError.sessionTooShort
        }
        if sessionDuration <= 50 * 60 {
            return [
                FocusInterval(
                    kind: .work,
                    start: configuration.start,
                    end: configuration.end
                ),
            ]
        }

        guard (25...30).contains(configuration.readingBreakMinutes) else {
            throw SchedulePlanningError.invalidReadingBreakDuration
        }

        let workDuration = TimeInterval(50 * 60)
        let shortBreakDuration = TimeInterval(10 * 60)
        let readingBreakDuration = TimeInterval(configuration.readingBreakMinutes * 60)
        let lunchDuration = TimeInterval(45 * 60)
        if let lunchWindow = configuration.lunchWindow,
           lunchWindow.duration < lunchDuration {
            throw SchedulePlanningError.invalidLunchWindow
        }

        let busyIntervals = configuration.busyIntervals
            .filter { $0.isBusy && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var intervals: [FocusInterval] = []
        var cursor = configuration.start
        var completedWorkBlocks = 0
        var lunchScheduled = configuration.lunchWindow == nil

        while cursor.addingTimeInterval(workDuration) <= configuration.end {
            let workEnd = cursor.addingTimeInterval(workDuration)
            intervals.append(FocusInterval(kind: .work, start: cursor, end: workEnd))
            cursor = workEnd
            completedWorkBlocks += 1

            let readingDue = completedWorkBlocks.isMultiple(of: 2)
            var lunchAdded = false
            if let lunchWindow = configuration.lunchWindow,
               lunchScheduled == false,
               shouldScheduleLunch(
                   after: cursor,
                   window: lunchWindow,
                   readingDue: readingDue,
                   readingDuration: readingBreakDuration,
                   workDuration: workDuration,
                   shortBreakDuration: shortBreakDuration,
                   sessionEnd: configuration.end,
                   busyIntervals: busyIntervals
               ) {
                let lunchStart = nextAvailableStart(
                    from: max(cursor, lunchWindow.start),
                    duration: lunchDuration,
                    busyIntervals: busyIntervals
                )
                let lunchEnd = lunchStart.addingTimeInterval(lunchDuration)
                guard lunchEnd <= lunchWindow.end, lunchEnd <= configuration.end else {
                    throw SchedulePlanningError.lunchCannotFit
                }
                intervals.append(FocusInterval(kind: .lunch, start: lunchStart, end: lunchEnd))
                cursor = lunchEnd
                lunchScheduled = true
                lunchAdded = true
            }

            if readingDue {
                let readingStart = nextAvailableStart(
                    from: cursor,
                    duration: readingBreakDuration,
                    busyIntervals: busyIntervals
                )
                let readingEnd = readingStart.addingTimeInterval(readingBreakDuration)
                guard readingEnd <= configuration.end else {
                    throw SchedulePlanningError.protectedBreakExceedsSession
                }
                intervals.append(
                    FocusInterval(kind: .readingBreak, start: readingStart, end: readingEnd)
                )
                cursor = readingEnd
                continue
            }

            if lunchAdded {
                continue
            }

            let shortBreakStart = nextAvailableStart(
                from: cursor,
                duration: shortBreakDuration,
                busyIntervals: busyIntervals
            )
            let shortBreakEnd = shortBreakStart.addingTimeInterval(shortBreakDuration)
            let followingWorkEnd = shortBreakEnd.addingTimeInterval(workDuration)
            guard followingWorkEnd <= configuration.end else {
                break
            }
            intervals.append(
                FocusInterval(kind: .shortBreak, start: shortBreakStart, end: shortBreakEnd)
            )
            cursor = shortBreakEnd
        }

        guard lunchScheduled else {
            throw SchedulePlanningError.lunchCannotFit
        }
        return intervals
    }

    private func shouldScheduleLunch(
        after cursor: Date,
        window: DateInterval,
        readingDue: Bool,
        readingDuration: TimeInterval,
        workDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        sessionEnd: Date,
        busyIntervals: [BusyInterval]
    ) -> Bool {
        if cursor >= window.start {
            return true
        }

        let normalBreakDuration = readingDue ? readingDuration : shortBreakDuration
        let normalBreakStart = nextAvailableStart(
            from: cursor,
            duration: normalBreakDuration,
            busyIntervals: busyIntervals
        )
        let nextWorkBoundary = normalBreakStart
            .addingTimeInterval(normalBreakDuration + workDuration)
        let futureLunchStart = max(nextWorkBoundary, window.start)
        let futureLunchEnd = futureLunchStart.addingTimeInterval(45 * 60)

        return nextWorkBoundary > sessionEnd || futureLunchEnd > window.end
    }

    private func nextAvailableStart(
        from proposedStart: Date,
        duration: TimeInterval,
        busyIntervals: [BusyInterval]
    ) -> Date {
        var candidate = proposedStart

        while true {
            let candidateEnd = candidate.addingTimeInterval(duration)
            let overlappingEnd = busyIntervals
                .filter { interval in
                    interval.start < candidateEnd && interval.end > candidate
                }
                .map(\.end)
                .max()

            guard let overlappingEnd else {
                return candidate
            }
            candidate = overlappingEnd
        }
    }
}
