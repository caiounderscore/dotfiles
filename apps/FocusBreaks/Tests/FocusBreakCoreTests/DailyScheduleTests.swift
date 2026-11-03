import Foundation
import Testing
@testable import FocusBreakCore

struct DailyScheduleTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test("schedules lunch at the first cadence boundary that fits its window")
    func schedulesLunchInWindow() throws {
        let intervals = try SchedulePlanner().plan(
            .init(
                start: start,
                end: minute(420),
                readingBreakMinutes: 30,
                lunchWindow: DateInterval(start: minute(180), end: minute(260))
            )
        )

        let lunch = try #require(intervals.first { $0.kind == .lunch })
        #expect(lunch.start == minute(190))
        #expect(lunch.end == minute(235))
    }

    @Test("keeps lunch before reading when both are due")
    func keepsLunchAndReadingSeparate() throws {
        let intervals = try SchedulePlanner().plan(
            .init(
                start: start,
                end: minute(360),
                readingBreakMinutes: 30,
                lunchWindow: DateInterval(start: minute(100), end: minute(200))
            )
        )

        let kinds = intervals.map(\.kind)
        #expect(Array(kinds.prefix(5)) == [.work, .shortBreak, .work, .lunch, .readingBreak])
        #expect(intervals[3].duration == 45 * 60)
        #expect(intervals[4].duration == 30 * 60)
    }

    @Test("rejects a lunch window shorter than 45 minutes")
    func rejectsShortLunchWindow() {
        #expect(throws: SchedulePlanningError.invalidLunchWindow) {
            try SchedulePlanner().plan(
                .init(
                    start: start,
                    end: minute(300),
                    readingBreakMinutes: 30,
                    lunchWindow: DateInterval(start: minute(100), end: minute(140))
                )
            )
        }
    }

    @Test("defers a reading break until a busy event ends without restarting work")
    func defersReadingBreak() throws {
        let intervals = try SchedulePlanner().plan(
            .init(
                start: start,
                end: minute(300),
                readingBreakMinutes: 30,
                busyIntervals: [
                    BusyInterval(start: minute(100), end: minute(130), isBusy: true),
                ]
            )
        )

        let reading = try #require(intervals.first { $0.kind == .readingBreak })
        #expect(intervals[2].kind == .work)
        #expect(intervals[2].end == minute(110))
        #expect(reading.start == minute(130))
        #expect(reading.end == minute(160))
    }

    @Test("defers across chained busy events")
    func defersAcrossChainedBusyEvents() throws {
        let intervals = try SchedulePlanner().plan(
            .init(
                start: start,
                end: minute(320),
                readingBreakMinutes: 30,
                busyIntervals: [
                    BusyInterval(start: minute(105), end: minute(120), isBusy: true),
                    BusyInterval(start: minute(119), end: minute(140), isBusy: true),
                ]
            )
        )

        let reading = try #require(intervals.first { $0.kind == .readingBreak })
        #expect(reading.start == minute(140))
    }

    @Test("ignores calendar intervals marked free")
    func ignoresFreeCalendarIntervals() throws {
        let intervals = try SchedulePlanner().plan(
            .init(
                start: start,
                end: minute(280),
                readingBreakMinutes: 30,
                busyIntervals: [
                    BusyInterval(start: minute(100), end: minute(130), isBusy: false),
                ]
            )
        )

        let reading = try #require(intervals.first { $0.kind == .readingBreak })
        #expect(reading.start == minute(110))
    }

    @Test("reports a protected break that busy time pushes past session end")
    func rejectsProtectedBreakPastSessionEnd() {
        #expect(throws: SchedulePlanningError.protectedBreakExceedsSession) {
            try SchedulePlanner().plan(
                .init(
                    start: start,
                    end: minute(150),
                    readingBreakMinutes: 30,
                    busyIntervals: [
                        BusyInterval(start: minute(100), end: minute(130), isBusy: true),
                    ]
                )
            )
        }
    }

    @Test("reports lunch that cannot fit after busy-time deferral")
    func rejectsLunchPastWindow() {
        #expect(throws: SchedulePlanningError.lunchCannotFit) {
            try SchedulePlanner().plan(
                .init(
                    start: start,
                    end: minute(300),
                    readingBreakMinutes: 30,
                    lunchWindow: DateInterval(start: minute(100), end: minute(180)),
                    busyIntervals: [
                        BusyInterval(start: minute(100), end: minute(150), isBusy: true),
                    ]
                )
            )
        }
    }

    @Test("preview proposes calendar writes for reading and lunch only")
    func limitsCalendarWriteProposals() throws {
        let intervals = try SchedulePlanner().plan(
            .init(
                start: start,
                end: minute(420),
                readingBreakMinutes: 30,
                lunchWindow: DateInterval(start: minute(180), end: minute(260))
            )
        )

        let preview = SchedulePreview(intervals: intervals)

        #expect(preview.calendarWrites.isEmpty == false)
        #expect(preview.calendarWrites.allSatisfy {
            $0.kind == .readingBreak || $0.kind == .lunch
        })
        #expect(preview.calendarWrites.contains { $0.kind == .readingBreak })
        #expect(preview.calendarWrites.contains { $0.kind == .lunch })
    }

    private func minute(_ value: Int) -> Date {
        start.addingTimeInterval(TimeInterval(value * 60))
    }
}
