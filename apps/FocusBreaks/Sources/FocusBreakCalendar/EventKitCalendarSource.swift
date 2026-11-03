@preconcurrency import EventKit
import Foundation

@MainActor
public final class EventKitCalendarSource: CalendarEventSourcing {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    public func events(from start: Date, to end: Date) async -> CalendarSourceResult {
        guard start < end else { return .unavailable }

        do {
            guard try await hasFullAccess() else { return .denied }
        } catch {
            return .unavailable
        }

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        let records = eventStore.events(matching: predicate).map { event in
            CalendarEventRecord(
                start: event.startDate,
                end: event.endDate,
                isBusy: event.availability != .free
            )
        }
        return .events(records)
    }

    private func hasFullAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return try await eventStore.requestFullAccessToEvents()
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }
}
