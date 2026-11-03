import Foundation

public struct CalendarEventRecord: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let isBusy: Bool

    public init(start: Date, end: Date, isBusy: Bool) {
        self.start = start
        self.end = end
        self.isBusy = isBusy
    }
}

public enum CalendarSourceResult: Equatable, Sendable {
    case events([CalendarEventRecord])
    case denied
    case unavailable
}

@MainActor
public protocol CalendarEventSourcing: AnyObject {
    func events(from start: Date, to end: Date) async -> CalendarSourceResult
}

public struct CalendarOperatingMode: Equatable, Sendable {
    public let localTimersEnabled: Bool
    public let calendarWritesEnabled: Bool
    public let warning: String?

    public static let readOnly = CalendarOperatingMode(
        localTimersEnabled: true,
        calendarWritesEnabled: false,
        warning: nil
    )

    public static let degraded = CalendarOperatingMode(
        localTimersEnabled: true,
        calendarWritesEnabled: false,
        warning: "Calendar coordination is unavailable. Local timers remain active; calendar writes are disabled."
    )
}

public struct CalendarReadResult: Equatable, Sendable {
    public let busyIntervals: [CalendarEventRecord]
    public let mode: CalendarOperatingMode
}

@MainActor
public final class CalendarCoordinator {
    private let source: any CalendarEventSourcing

    public init(source: any CalendarEventSourcing) {
        self.source = source
    }

    public func readBusyIntervals(from start: Date, to end: Date) async -> CalendarReadResult {
        switch await source.events(from: start, to: end) {
        case let .events(events):
            return CalendarReadResult(
                busyIntervals: events.filter(\.isBusy),
                mode: .readOnly
            )
        case .denied, .unavailable:
            return CalendarReadResult(busyIntervals: [], mode: .degraded)
        }
    }
}

public struct CalendarDescriptor: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let sourceTitle: String
    public let isWritable: Bool

    public init(
        identifier: String,
        title: String,
        sourceTitle: String,
        isWritable: Bool
    ) {
        self.identifier = identifier
        self.title = title
        self.sourceTitle = sourceTitle
        self.isWritable = isWritable
    }
}

public enum TargetCalendarResolutionError: Error, Equatable {
    case savedCalendarUnavailable
}

public enum TargetCalendarResolver {
    public static func resolve(
        savedIdentifier: String,
        calendars: [CalendarDescriptor],
        expectedTitle: String = "Focus & Breaks"
    ) throws -> CalendarDescriptor {
        guard let calendar = calendars.first(where: {
            $0.identifier == savedIdentifier
                && $0.title == expectedTitle
                && $0.isWritable
        }) else {
            throw TargetCalendarResolutionError.savedCalendarUnavailable
        }
        return calendar
    }
}
