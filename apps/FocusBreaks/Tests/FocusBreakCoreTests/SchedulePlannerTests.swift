import Foundation
import Testing
@testable import FocusBreakCore

struct SchedulePlannerTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test("uses 50/10 cadence and replaces every second short break with reading")
    func plansCadence() throws {
        let end = start.addingTimeInterval(280 * 60)

        let intervals = try SchedulePlanner().plan(
            .init(start: start, end: end, readingBreakMinutes: 30)
        )

        #expect(intervals.map(\.kind) == [
            .work,
            .shortBreak,
            .work,
            .readingBreak,
            .work,
            .shortBreak,
            .work,
            .readingBreak,
        ])
        #expect(intervals.filter { $0.kind == .work }.allSatisfy { $0.duration == 50 * 60 })
        #expect(intervals.filter { $0.kind == .shortBreak }.allSatisfy { $0.duration == 10 * 60 })
        #expect(intervals.filter { $0.kind == .readingBreak }.allSatisfy { $0.duration == 30 * 60 })
    }

    @Test("supports a 25-minute reading break")
    func plansConfigurableReadingDuration() throws {
        let end = start.addingTimeInterval(275 * 60)

        let intervals = try SchedulePlanner().plan(
            .init(start: start, end: end, readingBreakMinutes: 25)
        )

        let readingDurations = intervals
            .filter { $0.kind == .readingBreak }
            .map(\.duration)
        #expect(readingDurations == [TimeInterval(25 * 60), TimeInterval(25 * 60)])
        #expect(intervals.filter { $0.kind == .work }.count == 4)
    }

    @Test("does not add a break unless another complete work block fits")
    func respectsSessionEnd() throws {
        let end = start.addingTimeInterval(245 * 60)

        let intervals = try SchedulePlanner().plan(
            .init(start: start, end: end, readingBreakMinutes: 30)
        )

        #expect(intervals.map(\.kind) == [
            .work,
            .shortBreak,
            .work,
            .readingBreak,
            .work,
        ])
        #expect(intervals.last?.end == start.addingTimeInterval(190 * 60))
        #expect(intervals.allSatisfy { $0.end <= end })
    }

    @Test("uses the selected end time for a session shorter than the default work block")
    func plansShortSession() throws {
        let end = start.addingTimeInterval(20 * 60)

        let intervals = try SchedulePlanner().plan(
            .init(
                start: start,
                end: end,
                readingBreakMinutes: 24,
                lunchWindow: DateInterval(
                    start: start,
                    end: start.addingTimeInterval(10 * 60)
                )
            )
        )

        #expect(intervals == [FocusInterval(kind: .work, start: start, end: end)])
        #expect(SchedulePreview(intervals: intervals).calendarWrites.isEmpty)
    }

    @Test("rejects a session whose end is not later than its start")
    func rejectsNonPositiveSession() {
        #expect(throws: SchedulePlanningError.sessionTooShort) {
            try SchedulePlanner().plan(
                .init(start: start, end: start, readingBreakMinutes: 30)
            )
        }
    }

    @Test(arguments: [24, 31])
    func rejectsReadingDurationOutsideAcceptedRange(minutes: Int) {
        let end = start.addingTimeInterval(260 * 60)

        #expect(throws: SchedulePlanningError.invalidReadingBreakDuration) {
            try SchedulePlanner().plan(
                .init(start: start, end: end, readingBreakMinutes: minutes)
            )
        }
    }
}
