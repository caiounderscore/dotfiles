import FocusBreakCalendar
import FocusBreakCore
import Foundation
import Testing
@testable import FocusBreakUI

@MainActor
struct DailyPreflightModelTests {
    @Test("short sessions use the selected boundary without calendar writes")
    func previewsShortSession() async throws {
        let sender = PreflightCommandSender()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .events([]))
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let end = start.addingTimeInterval(20 * 60)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            sessionStart: start,
            sessionEnd: end,
            lunchStart: start,
            lunchEnd: start.addingTimeInterval(10 * 60),
            readingBreakMinutes: 25
        )

        await model.generatePreview(localDay: "2026-07-20")

        #expect(model.usesShortSessionDefaults)
        #expect(model.plan?.intervals == [
            FocusInterval(kind: .work, start: start, end: end),
        ])
        #expect(model.calendarWrites.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("generates and confirms an exact daily preview before starting")
    func confirmsPreview() async throws {
        let sender = PreflightCommandSender()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .events([]))
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(8 * 60 * 60),
            lunchStart: start.addingTimeInterval(3 * 60 * 60),
            lunchEnd: start.addingTimeInterval(5 * 60 * 60),
            readingBreakMinutes: 30
        )

        await model.generatePreview(localDay: "2026-07-20")
        try await model.confirmAndStart()

        let plan = try #require(model.plan)
        #expect(plan.intervals.isEmpty == false)
        #expect(model.calendarWrites.allSatisfy {
            $0.kind == .readingBreak || $0.kind == .lunch
        })
        #expect(sender.configuredPlans == [plan])
        #expect(sender.commands == [.start])
        #expect(model.confirmed)
    }

    @Test("regular sessions can omit lunch without removing reading breaks")
    func omitsLunch() async throws {
        let sender = PreflightCommandSender()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .events([]))
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(8 * 60 * 60),
            scheduleLunch: false,
            lunchStart: start.addingTimeInterval(5 * 60 * 60),
            lunchEnd: start.addingTimeInterval(3 * 60 * 60),
            readingBreakMinutes: 30
        )

        await model.generatePreview(localDay: "2026-07-20")

        let intervals = try #require(model.plan?.intervals)
        #expect(intervals.contains { $0.kind == .lunch } == false)
        #expect(intervals.contains { $0.kind == .readingBreak })
        #expect(model.calendarWrites.allSatisfy { $0.kind == .readingBreak })
        #expect(model.errorMessage == nil)
    }

    @Test("changing lunch selection invalidates a generated preview")
    func lunchSelectionInvalidatesPreview() async {
        let sender = PreflightCommandSender()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .events([]))
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(8 * 60 * 60),
            lunchStart: start.addingTimeInterval(3 * 60 * 60),
            lunchEnd: start.addingTimeInterval(5 * 60 * 60),
            readingBreakMinutes: 30
        )

        await model.generatePreview(localDay: "2026-07-20")
        #expect(model.preview != nil)

        model.scheduleLunch = false

        #expect(model.preview == nil)
        #expect(model.plan == nil)
        #expect(model.confirmed == false)
    }

    @Test("reset restores default lunch and clears stale planning state")
    func resetsForAnotherSession() async {
        let sender = PreflightCommandSender()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .events([]))
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(8 * 60 * 60),
            scheduleLunch: false,
            lunchStart: start.addingTimeInterval(3 * 60 * 60),
            lunchEnd: start.addingTimeInterval(5 * 60 * 60),
            readingBreakMinutes: 25
        )
        await model.generatePreview(localDay: "2026-07-20")

        let nextStart = start.addingTimeInterval(10 * 60 * 60)
        model.reset(
            sessionStart: nextStart,
            sessionEnd: nextStart.addingTimeInterval(4 * 60 * 60),
            lunchStart: nextStart.addingTimeInterval(60 * 60),
            lunchEnd: nextStart.addingTimeInterval(2 * 60 * 60)
        )

        #expect(model.sessionStart == nextStart)
        #expect(model.scheduleLunch)
        #expect(model.readingBreakMinutes == 30)
        #expect(model.preview == nil)
        #expect(model.plan == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("surfaces degraded calendar mode while preserving the local preview")
    func showsDegradedWarning() async {
        let sender = PreflightCommandSender()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .denied)
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(8 * 60 * 60),
            lunchStart: start.addingTimeInterval(3 * 60 * 60),
            lunchEnd: start.addingTimeInterval(5 * 60 * 60),
            readingBreakMinutes: 25
        )

        await model.generatePreview(localDay: "2026-07-20")

        #expect(model.plan != nil)
        #expect(model.degradedWarning != nil)
        #expect(model.calendarWritesEnabled == false)
    }

    @Test("surfaces denied notification authorization during preflight")
    func showsNotificationWarning() async {
        let sender = PreflightCommandSender()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .events([]))
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            notificationAuthorizer: PreflightNotificationAuthorizer(authorized: false),
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(8 * 60 * 60),
            lunchStart: start.addingTimeInterval(3 * 60 * 60),
            lunchEnd: start.addingTimeInterval(5 * 60 * 60),
            readingBreakMinutes: 25
        )

        await model.generatePreview(localDay: "2026-07-20")

        #expect(model.plan != nil)
        #expect(model.notificationWarning != nil)
    }

    @Test("writes only the confirmed reading and lunch proposal to the selected target")
    func writesConfirmedProposal() async throws {
        let sender = PreflightCommandSender()
        let writeStore = PreflightCalendarWriteStore()
        let calendar = CalendarCoordinator(
            source: PreflightCalendarSource(result: .events([]))
        )
        let start = Date(timeIntervalSince1970: 1_721_481_200)
        let model = DailyPreflightModel(
            sender: sender,
            calendar: calendar,
            calendarWriteStore: writeStore,
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(8 * 60 * 60),
            lunchStart: start.addingTimeInterval(3 * 60 * 60),
            lunchEnd: start.addingTimeInterval(5 * 60 * 60),
            readingBreakMinutes: 30
        )

        await model.generatePreview(localDay: "2026-07-20")
        model.selectedCalendarIdentifier = "work-1"
        try await model.confirmAndStart()

        #expect(writeStore.saved.count == model.calendarWrites.count)
        #expect(writeStore.saved.allSatisfy {
            $0.title == "Reading break" || $0.title == "Lunch break"
        })
        #expect(model.calendarWriteResult?.isComplete == true)
    }
}

@MainActor
private final class PreflightNotificationAuthorizer: NotificationAuthorizing {
    let authorized: Bool

    init(authorized: Bool) {
        self.authorized = authorized
    }

    func requestAuthorization() async throws -> Bool {
        authorized
    }
}

@MainActor
private final class PreflightCalendarWriteStore: CalendarWriteStoring {
    let calendars = [
        CalendarDescriptor(
            identifier: "work-1",
            title: "Focus & Breaks",
            sourceTitle: "caio@example.com",
            isWritable: true
        ),
    ]
    private(set) var saved: [CalendarWriteRecord] = []

    func existingRecordIdentifiers(
        in calendarIdentifier: String,
        from start: Date,
        to end: Date
    ) -> Set<String> {
        []
    }

    func save(_ record: CalendarWriteRecord, to calendarIdentifier: String) throws {
        saved.append(record)
    }
}

private extension CalendarWriteResult {
    var isComplete: Bool {
        if case .completed = self { return true }
        return false
    }
}

@MainActor
private final class PreflightCalendarSource: CalendarEventSourcing {
    let result: CalendarSourceResult

    init(result: CalendarSourceResult) {
        self.result = result
    }

    func events(from start: Date, to end: Date) async -> CalendarSourceResult {
        result
    }
}

@MainActor
private final class PreflightCommandSender: SessionCommandSending {
    private(set) var configuredPlans: [DailySessionPlan] = []
    private(set) var commands: [SessionCommand] = []

    func configure(_ plan: DailySessionPlan) async throws -> SessionSnapshot {
        configuredPlans.append(plan)
        return SessionSnapshot()
    }

    func send(_ command: SessionCommand) async throws -> SessionSnapshot {
        commands.append(command)
        return SessionSnapshot(
            sessionID: UUID(),
            phase: .working,
            revision: commands.count
        )
    }
}
