import FocusBreakCalendar
import FocusBreakCore
import Foundation
import Observation

@MainActor
@Observable
public final class DailyPreflightModel {
    public var sessionStart: Date {
        didSet { invalidatePreview() }
    }
    public var sessionEnd: Date {
        didSet { invalidatePreview() }
    }
    public var scheduleLunch: Bool {
        didSet { invalidatePreview() }
    }
    public var lunchStart: Date {
        didSet { invalidatePreview() }
    }
    public var lunchEnd: Date {
        didSet { invalidatePreview() }
    }
    public var readingBreakMinutes: Int {
        didSet { invalidatePreview() }
    }
    public var selectedCalendarIdentifier: String?

    public private(set) var plan: DailySessionPlan?
    public private(set) var preview: SchedulePreview?
    public private(set) var degradedWarning: String?
    public private(set) var notificationWarning: String?
    public private(set) var calendarWritesEnabled = false
    public private(set) var availableTargetCalendars: [CalendarDescriptor] = []
    public private(set) var calendarWriteResult: CalendarWriteResult?
    public private(set) var confirmed = false
    public private(set) var errorMessage: String?

    @ObservationIgnored
    private let sender: any SessionCommandSending
    @ObservationIgnored
    private let calendar: CalendarCoordinator
    @ObservationIgnored
    private let notificationAuthorizer: (any NotificationAuthorizing)?
    @ObservationIgnored
    private let calendarWriteStore: (any CalendarWriteStoring)?
    @ObservationIgnored
    private let calendarWriter: ApprovedCalendarWriter?
    @ObservationIgnored
    private let planner = SchedulePlanner()

    public init(
        sender: any SessionCommandSending,
        calendar: CalendarCoordinator,
        calendarWriteStore: (any CalendarWriteStoring)? = nil,
        notificationAuthorizer: (any NotificationAuthorizing)? = nil,
        sessionStart: Date,
        sessionEnd: Date,
        scheduleLunch: Bool = true,
        lunchStart: Date,
        lunchEnd: Date,
        readingBreakMinutes: Int
    ) {
        self.sender = sender
        self.calendar = calendar
        self.notificationAuthorizer = notificationAuthorizer
        self.calendarWriteStore = calendarWriteStore
        calendarWriter = calendarWriteStore.map(ApprovedCalendarWriter.init(store:))
        self.sessionStart = sessionStart
        self.sessionEnd = sessionEnd
        self.scheduleLunch = scheduleLunch
        self.lunchStart = lunchStart
        self.lunchEnd = lunchEnd
        self.readingBreakMinutes = readingBreakMinutes
    }

    public var calendarWrites: [FocusInterval] {
        preview?.calendarWrites ?? []
    }

    public var usesShortSessionDefaults: Bool {
        let duration = sessionEnd.timeIntervalSince(sessionStart)
        return duration > 0 && duration <= 50 * 60
    }

    public var calendarTargetWarning: String? {
        guard calendarWriteStore != nil else { return nil }
        if availableTargetCalendars.isEmpty {
            return "No writable calendar named Focus & Breaks is visible to macOS. Local timers can still start."
        }
        if selectedCalendarIdentifier == nil {
            return "Select the exact Fastmail Focus & Breaks calendar for this day's writes."
        }
        return nil
    }

    public func generatePreview(localDay: String) async {
        confirmed = false
        calendarWritesEnabled = false
        calendarWriteResult = nil
        errorMessage = nil
        notificationWarning = nil

        if let notificationAuthorizer {
            do {
                if try await notificationAuthorizer.requestAuthorization() == false {
                    notificationWarning = "Notifications are disabled. Enable them in System Settings so break reminders can be delivered."
                }
            } catch {
                notificationWarning = "Notification authorization could not be verified."
            }
        }

        let calendarResult = await calendar.readBusyIntervals(
            from: sessionStart,
            to: sessionEnd
        )
        degradedWarning = calendarResult.mode.warning
        availableTargetCalendars = calendarWriteStore?.calendars.filter {
            $0.title == "Focus & Breaks"
                && $0.isWritable
        } ?? []
        if availableTargetCalendars.count == 1 {
            selectedCalendarIdentifier = availableTargetCalendars[0].identifier
        }

        do {
            let intervals = try planner.plan(
                ScheduleConfiguration(
                    start: sessionStart,
                    end: sessionEnd,
                    readingBreakMinutes: readingBreakMinutes,
                    lunchWindow: scheduleLunch
                        ? DateInterval(start: lunchStart, end: lunchEnd)
                        : nil,
                    busyIntervals: calendarResult.busyIntervals.map {
                        BusyInterval(start: $0.start, end: $0.end, isBusy: $0.isBusy)
                    }
                )
            )
            let preview = SchedulePreview(intervals: intervals)
            self.preview = preview
            plan = try DailySessionPlan(localDay: localDay, intervals: intervals)
        } catch {
            preview = nil
            plan = nil
            errorMessage = Self.message(for: error)
        }
    }

    public func confirmAndStart() async throws {
        guard let previewPlan = plan else {
            throw SessionPlanError.invalidPlan
        }
        let confirmedPlan = try DailySessionPlan(
            localDay: previewPlan.localDay,
            intervals: previewPlan.intervals,
            selectedCalendarIdentifier: selectedCalendarIdentifier,
            calendarWritesConfirmed: selectedCalendarIdentifier != nil
                && degradedWarning == nil
        )
        plan = confirmedPlan
        _ = try await sender.configure(confirmedPlan)

        if let calendarWriter,
           let selectedCalendarIdentifier,
           degradedWarning == nil {
            let candidates = calendarWrites.compactMap(Self.writeCandidate)
            let result = await calendarWriter.write(
                candidates,
                configuration: CalendarWriteConfiguration(
                    enabled: true,
                    confirmedLocalDay: confirmedPlan.localDay,
                    currentLocalDay: confirmedPlan.localDay,
                    savedCalendarIdentifier: selectedCalendarIdentifier
                )
            )
            calendarWriteResult = result
            if case .completed = result {
                calendarWritesEnabled = true
            } else {
                degradedWarning = "Calendar writes did not complete. Local timers remain active; automatic retries are disabled."
            }
        }

        _ = try await sender.send(.start)
        confirmed = true
    }

    public func reset(
        sessionStart: Date,
        sessionEnd: Date,
        lunchStart: Date,
        lunchEnd: Date,
        readingBreakMinutes: Int = 30
    ) {
        self.sessionStart = sessionStart
        self.sessionEnd = sessionEnd
        scheduleLunch = true
        self.lunchStart = lunchStart
        self.lunchEnd = lunchEnd
        self.readingBreakMinutes = readingBreakMinutes
        selectedCalendarIdentifier = nil
        degradedWarning = nil
        notificationWarning = nil
        availableTargetCalendars = []
        invalidatePreview()
    }

    private func invalidatePreview() {
        plan = nil
        preview = nil
        calendarWriteResult = nil
        calendarWritesEnabled = false
        confirmed = false
        errorMessage = nil
    }

    private static func writeCandidate(
        for interval: FocusInterval
    ) -> CalendarWriteCandidate? {
        let kind: CalendarWriteCandidate.Kind
        switch interval.kind {
        case .readingBreak:
            kind = .reading
        case .lunch:
            kind = .lunch
        case .work, .shortBreak:
            return nil
        }
        return CalendarWriteCandidate(kind: kind, start: interval.start, end: interval.end)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case SchedulePlanningError.invalidLunchWindow:
            "The lunch window must be at least 45 minutes."
        case SchedulePlanningError.invalidReadingBreakDuration:
            "Reading breaks must be between 25 and 30 minutes."
        case SchedulePlanningError.lunchCannotFit:
            "Lunch cannot fit in the selected window."
        case SchedulePlanningError.protectedBreakExceedsSession:
            "A protected break would extend past the session end."
        case SchedulePlanningError.sessionTooShort:
            "The session end must be later than the session start."
        default:
            "The daily plan could not be generated."
        }
    }
}
