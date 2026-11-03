import Foundation

public struct CalendarWriteCandidate: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case reading
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
}

public struct CalendarWriteRecord: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let start: Date
    public let end: Date

    public init(identifier: String, title: String, start: Date, end: Date) {
        self.identifier = identifier
        self.title = title
        self.start = start
        self.end = end
    }

    public static func makeIdentifier(for candidate: CalendarWriteCandidate) -> String {
        let start = Int(candidate.start.timeIntervalSince1970)
        let duration = Int(candidate.end.timeIntervalSince(candidate.start))
        return "focus-breaks-\(candidate.kind.rawValue)-\(start)-\(duration)"
    }
}

public struct CalendarWriteConfiguration: Equatable, Sendable {
    public let enabled: Bool
    public let confirmedLocalDay: String?
    public let currentLocalDay: String
    public let savedCalendarIdentifier: String

    public init(
        enabled: Bool,
        confirmedLocalDay: String?,
        currentLocalDay: String,
        savedCalendarIdentifier: String
    ) {
        self.enabled = enabled
        self.confirmedLocalDay = confirmedLocalDay
        self.currentLocalDay = currentLocalDay
        self.savedCalendarIdentifier = savedCalendarIdentifier
    }
}

public enum CalendarWriteResult: Equatable, Sendable {
    case disabled
    case unavailable
    case completed(written: [String], alreadyPresent: [String])
    case partial(written: [String], failed: [String])
}

@MainActor
public protocol CalendarWriteStoring: AnyObject {
    var calendars: [CalendarDescriptor] { get }

    func existingRecordIdentifiers(
        in calendarIdentifier: String,
        from start: Date,
        to end: Date
    ) -> Set<String>
    func save(_ record: CalendarWriteRecord, to calendarIdentifier: String) throws
}

@MainActor
public final class ApprovedCalendarWriter {
    private let store: any CalendarWriteStoring

    public init(store: any CalendarWriteStoring) {
        self.store = store
    }

    public func write(
        _ candidates: [CalendarWriteCandidate],
        configuration: CalendarWriteConfiguration
    ) async -> CalendarWriteResult {
        guard configuration.enabled,
              configuration.confirmedLocalDay == configuration.currentLocalDay else {
            return .disabled
        }

        let calendar: CalendarDescriptor
        do {
            calendar = try TargetCalendarResolver.resolve(
                savedIdentifier: configuration.savedCalendarIdentifier,
                calendars: store.calendars
            )
        } catch {
            return .unavailable
        }

        guard let firstStart = candidates.map(\.start).min(),
              let lastEnd = candidates.map(\.end).max() else {
            return .completed(written: [], alreadyPresent: [])
        }

        var existing = store.existingRecordIdentifiers(
            in: calendar.identifier,
            from: firstStart,
            to: lastEnd
        )
        var written: [String] = []
        var alreadyPresent: [String] = []
        var failed: [String] = []

        for candidate in candidates where candidate.start < candidate.end {
            let record = Self.record(for: candidate)
            if existing.contains(record.identifier) {
                alreadyPresent.append(record.identifier)
                continue
            }
            do {
                try store.save(record, to: calendar.identifier)
                existing.insert(record.identifier)
                written.append(record.identifier)
            } catch {
                failed.append(record.identifier)
                break
            }
        }

        if failed.isEmpty {
            return .completed(written: written, alreadyPresent: alreadyPresent)
        }
        return .partial(written: written, failed: failed)
    }

    private static func record(for candidate: CalendarWriteCandidate) -> CalendarWriteRecord {
        CalendarWriteRecord(
            identifier: CalendarWriteRecord.makeIdentifier(for: candidate),
            title: candidate.kind == .reading ? "Reading break" : "Lunch break",
            start: candidate.start,
            end: candidate.end
        )
    }
}
