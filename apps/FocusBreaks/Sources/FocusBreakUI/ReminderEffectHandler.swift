import FocusBreakCore

@MainActor
public protocol NotificationPosting: AnyObject {
    func postBreak(_ presentation: BreakPresentation) async throws
    func postReturnToWork() async throws
    func postSessionComplete() async throws
}

@MainActor
public protocol OverlayControlling: AnyObject {
    func show(_ presentation: BreakPresentation)
    func hide()
}

extension OverlayController: OverlayControlling {}

@MainActor
public final class ReminderEffectHandler {
    private let notifications: any NotificationPosting
    private let overlays: any OverlayControlling

    public init(
        notifications: any NotificationPosting,
        overlays: any OverlayControlling
    ) {
        self.notifications = notifications
        self.overlays = overlays
    }

    public func handle(_ effect: ReminderEffect) async throws {
        switch effect {
        case let .deliverNotification(presentation):
            try await notifications.postBreak(presentation)
        case let .showOverlay(presentation):
            overlays.show(presentation)
        case .hideOverlay:
            overlays.hide()
        case .returnToWorkNotification:
            try await notifications.postReturnToWork()
        case .sessionCompleteNotification:
            try await notifications.postSessionComplete()
        case .skipped:
            break
        }
    }
}
