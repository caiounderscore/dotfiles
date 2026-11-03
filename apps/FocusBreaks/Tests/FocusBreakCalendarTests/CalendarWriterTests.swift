import FocusBreakCalendar
import Foundation
import Testing

@MainActor
struct CalendarWriterTests {
    @Test("writes remain disabled until same-day confirmation")
    func disabledByDefault() async {
        let store = FakeCalendarWriteStore()
        let writer = ApprovedCalendarWriter(store: store)
        let result = await writer.write(
            [fixtureCandidate()],
            configuration: CalendarWriteConfiguration(
                enabled: false,
                confirmedLocalDay: nil,
                currentLocalDay: "2026-07-20",
                savedCalendarIdentifier: "work-1"
            )
        )

        #expect(result == .disabled)
        #expect(store.saved.isEmpty)
    }

    @Test("suppresses a deterministic write that already exists")
    func suppressesRetry() async throws {
        let candidate = fixtureCandidate()
        let identifier = CalendarWriteRecord.makeIdentifier(for: candidate)
        let store = FakeCalendarWriteStore(existingIdentifiers: [identifier])
        let writer = ApprovedCalendarWriter(store: store)

        let result = await writer.write(
            [candidate],
            configuration: enabledConfiguration()
        )

        #expect(result == .completed(written: [], alreadyPresent: [identifier]))
        #expect(store.saved.isEmpty)
    }

    @Test("reports partial writes without retrying completed records")
    func reportsPartialWrite() async throws {
        let first = fixtureCandidate()
        let second = CalendarWriteCandidate(
            kind: .lunch,
            start: first.end.addingTimeInterval(60),
            end: first.end.addingTimeInterval(46 * 60)
        )
        let failedID = CalendarWriteRecord.makeIdentifier(for: second)
        let store = FakeCalendarWriteStore(failingIdentifiers: [failedID])
        let writer = ApprovedCalendarWriter(store: store)

        let result = await writer.write(
            [first, second],
            configuration: enabledConfiguration()
        )

        #expect(result == .partial(
            written: [CalendarWriteRecord.makeIdentifier(for: first)],
            failed: [failedID]
        ))
    }

    private func fixtureCandidate() -> CalendarWriteCandidate {
        CalendarWriteCandidate(
            kind: .reading,
            start: Date(timeIntervalSince1970: 1_721_488_400),
            end: Date(timeIntervalSince1970: 1_721_490_200)
        )
    }

    private func enabledConfiguration() -> CalendarWriteConfiguration {
        CalendarWriteConfiguration(
            enabled: true,
            confirmedLocalDay: "2026-07-20",
            currentLocalDay: "2026-07-20",
            savedCalendarIdentifier: "work-1"
        )
    }
}

@MainActor
private final class FakeCalendarWriteStore: CalendarWriteStoring {
    let calendars = [
        CalendarDescriptor(
            identifier: "work-1",
            title: "Focus & Breaks",
            sourceTitle: "Fastmail",
            isWritable: true
        ),
    ]
    var existingIdentifiers: Set<String>
    let failingIdentifiers: Set<String>
    private(set) var saved: [CalendarWriteRecord] = []

    init(
        existingIdentifiers: Set<String> = [],
        failingIdentifiers: Set<String> = []
    ) {
        self.existingIdentifiers = existingIdentifiers
        self.failingIdentifiers = failingIdentifiers
    }

    func existingRecordIdentifiers(
        in calendarIdentifier: String,
        from start: Date,
        to end: Date
    ) -> Set<String> {
        existingIdentifiers
    }

    func save(_ record: CalendarWriteRecord, to calendarIdentifier: String) throws {
        if failingIdentifiers.contains(record.identifier) {
            throw TestFailure.expected
        }
        saved.append(record)
        existingIdentifiers.insert(record.identifier)
    }
}

private enum TestFailure: Error {
    case expected
}
