import FocusBreakCore
@preconcurrency import UserNotifications

@MainActor
public protocol NotificationAuthorizing: AnyObject {
    func requestAuthorization() async throws -> Bool
}

@MainActor
public final class UserNotificationPoster:
    NotificationAuthorizing,
    NotificationPosting,
    FocusEndingWarningPosting
{
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    @discardableResult
    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func postBreak(_ presentation: BreakPresentation) async throws {
        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.body = presentation.guidance
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "focus-breaks.break.\(presentation.kind.rawValue)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    public func postReturnToWork() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Break complete"
        content.body = "Return when you are ready for the next focus block."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "focus-breaks.return-to-work",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    public func postSessionComplete() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Focus session complete"
        content.body = "Your planned focus time has ended."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "focus-breaks.session-complete",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    public func scheduleFocusEndingWarning(_ warning: FocusEndingWarning) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Focus block ending soon"
        content.body = "Five minutes remain. Finish your current thought and prepare for your break."
        content.sound = .default

        let delay = warning.fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        let request = UNNotificationRequest(
            identifier: warning.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        try await center.add(request)
    }

    public func cancelFocusEndingWarning(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
