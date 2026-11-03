@preconcurrency import EventKit
import Foundation

@MainActor
public final class EventKitCalendarWriteStore: CalendarWriteStoring {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    public var calendars: [CalendarDescriptor] {
        eventStore.calendars(for: .event).map { calendar in
            CalendarDescriptor(
                identifier: calendar.calendarIdentifier,
                title: calendar.title,
                sourceTitle: calendar.source.title,
                isWritable: calendar.allowsContentModifications
            )
        }
    }

    public func existingRecordIdentifiers(
        in calendarIdentifier: String,
        from start: Date,
        to end: Date
    ) -> Set<String> {
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
            return []
        }
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [calendar]
        )
        return Set(eventStore.events(matching: predicate).compactMap { event in
            guard event.url?.scheme == "focusbreaks",
                  event.url?.host == "record" else {
                return nil
            }
            return event.url?.lastPathComponent
        })
    }

    public func save(_ record: CalendarWriteRecord, to calendarIdentifier: String) throws {
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier),
              calendar.allowsContentModifications else {
            throw TargetCalendarResolutionError.savedCalendarUnavailable
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = record.title
        event.startDate = record.start
        event.endDate = record.end
        event.url = URL(string: "focusbreaks://record/\(record.identifier)")
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
}
