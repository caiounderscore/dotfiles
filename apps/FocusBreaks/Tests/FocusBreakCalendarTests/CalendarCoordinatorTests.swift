import FocusBreakCalendar
import Foundation
import Testing

@MainActor
struct CalendarCoordinatorTests {
    @Test("permission denial degrades safely without disabling local timers")
    func deniedPermissionDegradesSafely() async {
        let source = FakeCalendarSource(result: .denied)
        let coordinator = CalendarCoordinator(source: source)

        let result = await coordinator.readBusyIntervals(
            from: Date(timeIntervalSince1970: 100),
            to: Date(timeIntervalSince1970: 200)
        )

        #expect(result.busyIntervals.isEmpty)
        #expect(result.mode.localTimersEnabled)
        #expect(result.mode.calendarWritesEnabled == false)
        #expect(result.mode.warning != nil)
    }

    @Test("retains only start, end, and busy status from events")
    func minimizesEventData() async {
        let event = CalendarEventRecord(
            start: Date(timeIntervalSince1970: 120),
            end: Date(timeIntervalSince1970: 150),
            isBusy: true
        )
        let source = FakeCalendarSource(result: .events([event]))
        let coordinator = CalendarCoordinator(source: source)

        let result = await coordinator.readBusyIntervals(
            from: Date(timeIntervalSince1970: 100),
            to: Date(timeIntervalSince1970: 200)
        )

        #expect(result.busyIntervals == [event])
        #expect(result.mode.calendarWritesEnabled == false)
        #expect(result.mode.warning == nil)
    }
}

@MainActor
private final class FakeCalendarSource: CalendarEventSourcing {
    let result: CalendarSourceResult

    init(result: CalendarSourceResult) {
        self.result = result
    }

    func events(from start: Date, to end: Date) async -> CalendarSourceResult {
        result
    }
}
